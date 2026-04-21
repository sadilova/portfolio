#!/bin/bash
# ============================================================
# wrapper_preprocess.sh
# Full preprocessing pipeline wrapper
# ============================================================

# --- Pipeline flags ---
run_NORDIC=true
run_FIACH=true
MNI_space=true
SLICE_TIMING=false

# --- Selective processing ---
# Leave empty ("") to process everything, or set to filter:
#   TARGET_SUB="sub-01"   → only that subject
#   TARGET_CAP="cap2"     → only that subfolder (use "" to target direct-in-func files)
#   TARGET_RUN="run1"     → only that run name (as derived after stripping sub-XX_ prefix)
TARGET_SUB=""
TARGET_CAP=""
TARGET_RUN=""

# --- Restart / breakpoint control ---
# RESTART_FROM_STEP=0  → resume: use checkpoints, skip already-completed steps
# RESTART_FROM_STEP=N  → clear checkpoints from step N onward, rerun from step N
# RESTART_FROM_STEP=1  → clear all checkpoints, rerun everything from scratch
#
# Step reference:
#   1  NORDIC (commented out)    7  Combine regressors
#   2  Motion correction         8  Co-registration
#   3  Unwarping / mean func     9  Normalisation (8b)
#   4  Slice timing             10  Smoothing
#   5  Brain mask               11  tSNR maps
#   6  FIACH
RESTART_FROM_STEP=0

# --- Environment ---
export FSLDIR=$HOME/fsl
source $FSLDIR/etc/fslconf/fsl.sh
export PATH=$FSLDIR/bin:$PATH

DIR=$(cat 1_directory.txt)
export DIR
sDIR="$(dirname $(realpath $0))/preprocess/"
mapfile -t SUBS < 1_subjects.txt

# === Only need to run the first time ===
chmod +x ${sDIR}AS*.sh
echo "Installing Python dependencies..."
pip install -r 1_requirements.txt --break-system-packages

echo "============================================"
echo "Starting preprocessing pipeline"
echo "  Directory : ${DIR}"
echo "  Subjects  : ${SUBS[*]}"
[[ -n "$TARGET_SUB" ]] && echo "  Filter SUB: ${TARGET_SUB}"
[[ -n "$TARGET_CAP" ]] && echo "  Filter CAP: ${TARGET_CAP}"
[[ -n "$TARGET_RUN" ]] && echo "  Filter RUN: ${TARGET_RUN}"
[[ "$RESTART_FROM_STEP" -gt 0 ]] && echo "  Restart   : from step ${RESTART_FROM_STEP}"
echo "============================================"

bash ${sDIR}AS0_folder_org.sh


# ============================================================
# find_bold_files(func_dir)
#   Returns all *bold.nii.gz sorted:
#     1. Direct files in func/
#     2. Subfolders alphabetically (cap1 -> cap2 ...), runs sorted within each.
#   Empty folders are silently skipped.
# ============================================================
find_bold_files() {
    local func_dir="${1}"
    local -a results=()

    # Direct files in func/
    while IFS= read -r f; do
        [[ -n "$f" ]] && results+=("$f")
    done < <(find "${func_dir}" -maxdepth 1 -name "*bold.nii.gz" 2>/dev/null | sort)

    # Subfolders sorted (cap1, cap2, ...), runs sorted within each
    while IFS= read -r subdir; do
        [[ -z "$subdir" ]] && continue
        while IFS= read -r f; do
            [[ -n "$f" ]] && results+=("$f")
        done < <(find "${subdir}" -maxdepth 1 -name "*bold.nii.gz" 2>/dev/null | sort)
    done < <(find "${func_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

    printf '%s\n' "${results[@]}"
}


# ============================================================
# derive_run_info(func_dir, bold_path)
#   Prints two lines:
#     Line 1 — CAP_NAME : subfolder name (e.g. "cap1"), or "" if directly in func/
#     Line 2 — RUN_NAME : file base stripped of _bold suffix and any leading sub-XX_
#                         prefix, so sub-XX never appears twice in output filenames.
#   Examples:
#     func/run1_bold.nii.gz              -> CAP="",     RUN="run1"
#     func/sub-02_run-1_bold.nii.gz      -> CAP="",     RUN="run-1"
#     func/cap1/run1_bold.nii.gz         -> CAP="cap1", RUN="run1"
#     func/cap1/sub-02_run-1_bold.nii.gz -> CAP="cap1", RUN="run-1"
# ============================================================
derive_run_info() {
    local func_dir="${1}"
    local bold_path="${2}"
    local rel="${bold_path#${func_dir}/}"

    local cap_name="" run_file="" run_name=""

    if [[ "$rel" == */* ]]; then
        cap_name="${rel%%/*}"       # everything before first /  e.g. "cap1"
        run_file="${rel#*/}"        # everything after first /   e.g. "run1_bold.nii.gz"
    else
        run_file="$rel"
    fi

    run_name=$(basename "${run_file}" .nii.gz)           # strip .nii.gz
    run_name="${run_name%_bold}"                          # strip _bold suffix
    run_name=$(echo "${run_name}" | sed 's/^sub-[^_]*_//')  # strip leading sub-XX_

    printf '%s\n%s\n' "${cap_name}" "${run_name}"
}


# ============================================================
# Checkpoint helpers
#   Files: derivatives/SUB/preproc/checkpoints/RUN_LABEL/stepN.done
#
#   step_done N   — returns true if checkpoint file exists
#   mark_done N   — create checkpoint (call only on success via &&)
#   clear_from N  — delete checkpoints N..11 so those steps rerun
#   run_or_die N label cmd... — run cmd; mark done on success, exit on failure
# ============================================================
_ckpt_dir() {
    echo "${DIR}derivatives/${SUB}/preproc/checkpoints/${RUN_LABEL}"
}

step_done() {
    [[ -f "$(_ckpt_dir)/step_${1}.done" ]]
}

mark_done() {
    local cdir
    cdir=$(_ckpt_dir)
    mkdir -p "${cdir}"
    touch "${cdir}/step_${1}.done"
    echo "    v Step ${1} done"
}

clear_from_step() {
    local from="${1}" cdir
    cdir=$(_ckpt_dir)
    mkdir -p "${cdir}"
    for i in $(seq "${from}" 11); do
        rm -f "${cdir}/step_${i}.done"
    done
    echo "  Checkpoints cleared from step ${from} onward (${SUB}/${RUN_LABEL})"
}

run_or_die() {
    local step="${1}" label="${2}"; shift 2
    "$@" && mark_done "${step}" \
         || { echo "  ERROR: Step ${step} (${label}) failed."; \
              echo "         Fix the issue then rerun with RESTART_FROM_STEP=${step}"; \
              exit 1; }
}


# ============================================================
# SUBJECT LOOP
# ============================================================
for SUB in "${SUBS[@]}"; do
    export SUB

    # --- Subject filter ---
    if [[ -n "$TARGET_SUB" && "$SUB" != "$TARGET_SUB" ]]; then
        echo "Skipping ${SUB} (TARGET_SUB=${TARGET_SUB})"
        continue
    fi

    echo ""
    echo "============================================"
    echo "Subject: ${SUB}"
    echo "============================================"

    FUNC_DIR="${DIR}${SUB}/func"
    mapfile -t BOLD_FILES < <(find_bold_files "${FUNC_DIR}")

    if [[ ${#BOLD_FILES[@]} -eq 0 ]]; then
        echo "WARNING: No *bold.nii.gz found under ${FUNC_DIR} — skipping"
        continue
    fi

    echo "Found ${#BOLD_FILES[@]} bold file(s):"
    printf '  %s\n' "${BOLD_FILES[@]}"

    # ==========================================================
    # RUN LOOP
    # ==========================================================
    for BOLD_SRC in "${BOLD_FILES[@]}"; do

        # --- Derive CAP_NAME and RUN_NAME separately ---
        mapfile -t _run_info < <(derive_run_info "${FUNC_DIR}" "${BOLD_SRC}")
        CAP_NAME="${_run_info[0]}"    # "cap1" or ""
        RUN_NAME="${_run_info[1]}"    # "run1", "run-1", etc. — never contains sub-XX

        # RUN_LABEL: "cap1_run1" when in a subfolder, or just "run1" when direct
        if [[ -n "$CAP_NAME" ]]; then
            RUN_LABEL="${CAP_NAME}_${RUN_NAME}"
        else
            RUN_LABEL="${RUN_NAME}"
        fi
        export BOLD_SRC CAP_NAME RUN_NAME RUN_LABEL

        # --- Cap filter ---
        if [[ -n "$TARGET_CAP" && "$CAP_NAME" != "$TARGET_CAP" ]]; then
            echo "  Skipping ${RUN_LABEL} (TARGET_CAP=${TARGET_CAP})"
            continue
        fi

        # --- Run filter ---
        if [[ -n "$TARGET_RUN" && "$RUN_NAME" != "$TARGET_RUN" ]]; then
            echo "  Skipping ${RUN_LABEL} (TARGET_RUN=${TARGET_RUN})"
            continue
        fi

        echo ""
        echo "  ----------------------------------------"
        echo "  ${SUB} / ${RUN_LABEL}"
        [[ -n "$CAP_NAME" ]] && echo "  Cap: ${CAP_NAME}   Run: ${RUN_NAME}"
        echo "  Source: ${BOLD_SRC}"
        echo "  ----------------------------------------"

        # --- Clear checkpoints from restart point onward ---
        if [[ "$RESTART_FROM_STEP" -gt 0 ]]; then
            clear_from_step "${RESTART_FROM_STEP}"
        fi

        # -------------------------------------------------------
        # Pre-compute all pipeline filenames upfront.
        # Deterministic from flags — set once, valid for all steps.
        # -------------------------------------------------------
        if [ "$run_NORDIC" = true ]; then
            mc_file=NORDIC_Run_BOLD_${SUB}_${RUN_LABEL}
        else
            mc_file=Run_BOLD_${SUB}_${RUN_LABEL}
        fi

        if [ -d "${DIR}${SUB}/fmap/" ]; then
            sc_file=${mc_file}_mcf_unwarp
        else
            sc_file=${mc_file}_mcf
        fi

        if [ "$SLICE_TIMING" = true ]; then
            fiach_file=sc${sc_file}
        else
            fiach_file=${sc_file}
        fi

        if [ "$run_FIACH" = true ]; then
            reg_file=rclean_${fiach_file}
        else
            reg_file=${fiach_file}
        fi

        if [ "$MNI_space" = true ]; then
            smooth_file=norm_${reg_file}
        else
            smooth_file=reg_${reg_file}
        fi

        export mc_file sc_file fiach_file reg_file smooth_file

        # -------------------------------------------------------
        # STEP 1: Copy bold to NORDIC folder; apply NORDIC if enabled
        # -------------------------------------------------------
        if step_done 1; then
            echo "  Step 1: NORDIC/copy [SKIP]"
        else
            NORDIC_DIR="${DIR}derivatives/${SUB}/preproc/NORDIC"
            BOLD_COPY="${NORDIC_DIR}/Run_BOLD_${SUB}_${RUN_LABEL}.nii"
            echo "  Step 1: Copying bold to NORDIC folder..."
            gunzip -c "${BOLD_SRC}" > "${BOLD_COPY}" \
                || { echo "  ERROR: Step 1 — failed to copy bold"; exit 1; }

            if [ "$run_NORDIC" = true ]; then
                echo "  Step 1: Running NORDIC..."
                run_or_die 1 "NORDIC" \
                    matlab -nosplash -batch \
                        "cd('${sDIR}'); AS1_NIFTI_NORDIC('${DIR}','${SUB}','${RUN_LABEL}');"
            else
                echo "  Step 1: NORDIC [disabled by flag] — using raw bold"
                mark_done 1
            fi
        fi

        # -------------------------------------------------------
        # STEP 2: Motion correction
        # -------------------------------------------------------
        if step_done 2; then
            echo "  Step 2: Motion correction [SKIP]"
        else
            echo "  Step 2: Motion correction..."
            run_or_die 2 "Motion correction" \
                bash ${sDIR}AS2_realign_mcflirt_fsl.sh
        fi

        # -------------------------------------------------------
        # STEP 3: Unwarping  /  mean functional (no fmap)
        # -------------------------------------------------------
        if step_done 3; then
            echo "  Step 3: Unwarping/mean func [SKIP]"
        else
            OUTDIR="${DIR}derivatives/${SUB}/preproc/mc/"
            if [ -d "${DIR}${SUB}/fmap/" ]; then
                echo "  Step 3: Unwarping..."
                run_or_die 3 "Unwarping" \
                    bash ${sDIR}AS3_unwarping.sh
            else
                echo "  Step 3: No fmap — computing mean functional..."
                run_or_die 3 "Mean functional" bash -c "
                    fslmaths ${OUTDIR}${mc_file}_mcf.nii.gz \
                              -Tmean ${OUTDIR}meanFunctional_${RUN_LABEL}.nii.gz \
                    && gunzip -c ${OUTDIR}meanFunctional_${RUN_LABEL}.nii.gz \
                             > ${DIR}derivatives/${SUB}/preproc/FIACH/meanFunctional_${RUN_LABEL}.nii \
                    && gunzip -c ${OUTDIR}${mc_file}_mcf.nii.gz \
                             > ${DIR}derivatives/${SUB}/preproc/FIACH/${mc_file}_mcf.nii
                "
            fi
        fi

        # -------------------------------------------------------
        # STEP 4: Slice timing correction
        # -------------------------------------------------------
        if step_done 4; then
            echo "  Step 4: Slice timing [SKIP]"
        else
            if [ "$SLICE_TIMING" = true ]; then
                echo "  Step 4: Slice timing correction..."
                run_or_die 4 "Slice timing" \
                    bash ${sDIR}AS4_slice_timing_correction.sh
            else
                echo "  Step 4: Slice timing [disabled by flag]"
                mark_done 4
            fi
        fi

        # -------------------------------------------------------
        # STEP 5: Brain mask (T1)
        # -------------------------------------------------------
        if step_done 5; then
            echo "  Step 5: Brain mask [SKIP]"
        else
            T1_SRC=$(ls "${DIR}${SUB}/anat/"*T1w.nii.gz 2>/dev/null | head -n 1)
            if [[ ! -f "$T1_SRC" ]]; then
                echo "  ERROR: No T1w.nii.gz found for ${SUB} — cannot continue"
                exit 1
            fi
            echo "  Step 5: Brain mask..."
            run_or_die 5 "Brain mask" bash -c "
                gunzip -c '${T1_SRC}' \
                    > ${DIR}derivatives/${SUB}/preproc/FIACH/UNI_T1.nii \
                && python3 ${sDIR}AS5_maskbrain_ants.py
            "
        fi

        # -------------------------------------------------------
        # STEP 6: FIACH
        # STEP 7: Combine motion + FIACH regressors
        # -------------------------------------------------------
        if [ "$run_FIACH" = true ]; then
            if step_done 6; then
                echo "  Step 6: FIACH [SKIP]"
            else
                echo "  Step 6: FIACH..."

                # Resolve run-specific JSON (same path/basename as BOLD_SRC, .json extension)
                BOLD_JSON="${BOLD_SRC%.nii.gz}.json"
                if [[ ! -f "$BOLD_JSON" ]]; then
                    echo "  ERROR: No JSON sidecar found at ${BOLD_JSON}"
                    exit 1
                fi
                export BOLD_JSON

                MEAN_SRC="${DIR}derivatives/${SUB}/preproc/mc/meanFunctional_${RUN_LABEL}.nii.gz"
                [[ ! -f "$MEAN_SRC" ]] && \
                    MEAN_SRC="${DIR}derivatives/${SUB}/preproc/mc/meanFunctional.nii.gz"
                run_or_die 6 "FIACH" bash -c "
                    gunzip -c '${MEAN_SRC}' \
                        > ${DIR}derivatives/${SUB}/preproc/FIACH/meanFunctional.nii \
                    && bash ${sDIR}AS6_call_FIACH.sh
                "

                # Verify rclean was actually produced — MATLAB can exit 0 silently on error
                RCLEAN="${DIR}derivatives/${SUB}/preproc/FIACH/rclean_${fiach_file}.nii"
                if [[ ! -f "$RCLEAN" ]]; then
                    echo "  ERROR: Step 6 — FIACH ran but rclean_${fiach_file}.nii was not produced."
                    echo "         Check MATLAB output above. Rerun with RESTART_FROM_STEP=6"
                    rm -f "$(_ckpt_dir)/step_6.done"
                    exit 1
                fi
            fi

            if step_done 7; then
                echo "  Step 7: Combine regressors [SKIP]"
            else
                echo "  Step 7: Combine motion + FIACH regressors..."
                run_or_die 7 "Combine regressors" \
                    bash ${sDIR}AS7_combine_motion_regs_NORfi.sh
            fi
        else
            echo "  Steps 6-7: FIACH [disabled by flag]"
            step_done 6 || mark_done 6
            step_done 7 || mark_done 7
        fi

        # -------------------------------------------------------
        # STEP 8: Co-registration
        # -------------------------------------------------------
        if step_done 8; then
            echo "  Step 8: Co-registration [SKIP]"
        else
            echo "  Step 8: Co-registration..."
            run_or_die 8 "Co-registration" \
                python3 ${sDIR}AS8_coreg_func-T1.py
        fi

        # -------------------------------------------------------
        # STEP 9: Normalisation to MNI  (Step 8b in pipeline)
        # -------------------------------------------------------
        if step_done 9; then
            echo "  Step 8b: Normalisation [SKIP]"
        else
            echo "  Step 8b: Normalisation..."
            run_or_die 9 "Normalisation" \
                python3 ${sDIR}AS8b_reg_func-t1-mni.py
        fi

        # -------------------------------------------------------
        # STEP 10: Smoothing
        # -------------------------------------------------------
        if step_done 10; then
            echo "  Step 9: Smoothing [SKIP]"
        else
            echo "  Step 9: Smoothing ${smooth_file}..."
            run_or_die 10 "Smoothing" \
                bash ${sDIR}AS9_smoothing.sh
        fi

        # -------------------------------------------------------
        # STEP 11: tSNR maps
        # -------------------------------------------------------
        if step_done 11; then
            echo "  Step 10: tSNR [SKIP]"
        else
            echo "  Step 10: tSNR maps..."
            run_or_die 11 "tSNR" \
                bash ${sDIR}AS10_tsnr_maps.sh
        fi

        # --- Export pipeline variables for downstream QC ---
        STATS_DIR="${DIR}derivatives/${SUB}/stats"
        mkdir -p "${STATS_DIR}"
        ENV_FILE="${STATS_DIR}/pipeline_vars_${RUN_LABEL}.env"
        {
            echo "SUB=${SUB}"
            echo "DIR=${DIR}"
            echo "CAP_NAME=${CAP_NAME}"
            echo "RUN_NAME=${RUN_NAME}"
            echo "RUN_LABEL=${RUN_LABEL}"
            echo "BOLD_SRC=${BOLD_SRC}"
            echo "mc_file=${mc_file}"
            echo "sc_file=${sc_file}"
            echo "fiach_file=${fiach_file}"
            echo "reg_file=${reg_file}"
            echo "smooth_file=${smooth_file}"
        } > "${ENV_FILE}"

        echo "  Completed: ${SUB}/${RUN_LABEL}  (vars saved to ${ENV_FILE})"

    done  # end run loop

    echo ""
    echo "============================================"
    echo "All runs complete for: ${SUB}"
    echo "============================================"

done  # end subject loop

echo ""
echo "============================================"
echo "Pipeline complete for all subjects"
echo "============================================"
