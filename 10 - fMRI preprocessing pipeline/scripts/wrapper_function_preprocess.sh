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
#   1  NORDIC                    7  Combine regressors
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
# ============================================================
derive_run_info() {
    local func_dir="${1}"
    local bold_path="${2}"
    local rel="${bold_path#${func_dir}/}"

    local cap_name="" run_file="" run_name=""

    if [[ "$rel" == */* ]]; then
        cap_name="${rel%%/*}"
        run_file="${rel#*/}"
    else
        run_file="$rel"
    fi

    run_name=$(basename "${run_file}" .nii.gz)
    run_name="${run_name%_bold}"
    run_name=$(echo "${run_name}" | sed 's/^sub-[^_]*_//')

    printf '%s\n%s\n' "${cap_name}" "${run_name}"
}


# ============================================================
# Checkpoint helpers
#   Checkpoints are keyed by RUN_LABEL (which includes cap prefix,
#   e.g. "cap1_run1") so cap1 and cap2 never share checkpoints.
#   Files: derivatives/SUB/preproc/checkpoints/RUN_LABEL/stepN.done
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
        # Derive PREPROC_DIR (cap-aware) and T1_DIR (always subject-level)
        #   No cap → preproc/
        #   cap1   → preproc/cap1/
        # T1 is shared across caps so always lives at preproc/T1/
        # -------------------------------------------------------
        if [[ -n "$CAP_NAME" ]]; then
            PREPROC_DIR="${DIR}derivatives/${SUB}/preproc/${CAP_NAME}"
        else
            PREPROC_DIR="${DIR}derivatives/${SUB}/preproc"
        fi
        T1_DIR="${DIR}derivatives/${SUB}/preproc/T1"
        export PREPROC_DIR T1_DIR

        # Create all cap-specific subfolders for this run
        mkdir -p "${PREPROC_DIR}/mc" \
                 "${PREPROC_DIR}/NORDIC" \
                 "${PREPROC_DIR}/FIACH" \
                 "${PREPROC_DIR}/fmap" \
                 "${PREPROC_DIR}/reg" \
                 "${PREPROC_DIR}/smooth" \
                 "${PREPROC_DIR}/tsnr" \
                 "${PREPROC_DIR}/slicecor" \
                 "${T1_DIR}"

        echo "  Preproc dir: ${PREPROC_DIR}"

        # --- Resolve fmap directory for this run ---
        # Mirrors func folder structure:
        #   func/cap1/run1 → fmap/cap1/   (cap-specific)
        #   func/cap1/run1 → fmap/         (fallback: flat fmap applies to all caps)
        #   func/run1      → fmap/         (no cap subfolders)
        # If the expected fmap folder doesn't exist → skip unwarping
        FMAP_DIR=""
        FMAP_HAS_CAPS=$(find "${DIR}${SUB}/fmap" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)

        if [[ -n "$CAP_NAME" ]]; then
            if [ -d "${DIR}${SUB}/fmap/${CAP_NAME}/" ]; then
                # Cap-specific fmap subfolder exists
                FMAP_DIR="${DIR}${SUB}/fmap/${CAP_NAME}/"
                echo "  fmap: fmap/${CAP_NAME}/"
            elif [ -z "${FMAP_HAS_CAPS}" ] && [ -d "${DIR}${SUB}/fmap/" ]; then
                # fmap has no subfolders — use it for all caps
                FMAP_DIR="${DIR}${SUB}/fmap/"
                echo "  fmap: fmap/ (shared, no cap subfolders in fmap)"
            else
                echo "  fmap: fmap/${CAP_NAME}/ not found — skipping unwarping for ${RUN_LABEL}"
            fi
        else
            if [ -d "${DIR}${SUB}/fmap/" ]; then
                FMAP_DIR="${DIR}${SUB}/fmap/"
                echo "  fmap: fmap/"
            else
                echo "  fmap: none found — skipping unwarping"
            fi
        fi
        export FMAP_DIR

        # -------------------------------------------------------
        # Pre-compute all pipeline filenames upfront.
        # Deterministic from flags — set once, valid for all steps.
        # -------------------------------------------------------
        if [ "$run_NORDIC" = true ]; then
            mc_file=NORDIC_Run_BOLD_${SUB}_${RUN_NAME}
        else
            mc_file=Run_BOLD_${SUB}_${RUN_NAME}
        fi

        if [ -n "${FMAP_DIR}" ]; then
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
            NORDIC_DIR="${PREPROC_DIR}/NORDIC"
            BOLD_COPY="${NORDIC_DIR}/Run_BOLD_${SUB}_${RUN_NAME}.nii"
            echo "  Step 1: Copying bold to NORDIC folder..."
            gunzip -c "${BOLD_SRC}" > "${BOLD_COPY}" \
                || { echo "  ERROR: Step 1 — failed to copy bold"; exit 1; }

            if [ "$run_NORDIC" = true ]; then
                echo "  Step 1: Running NORDIC..."
                TMP_M="${NORDIC_DIR}/run_nordic_${RUN_NAME}.m"
                cat > "${TMP_M}" << MATLAB_EOF
cd('${sDIR}');
AS1_NIFTI_NORDIC('${DIR}', '${SUB}', '${RUN_NAME}', '${PREPROC_DIR}');
MATLAB_EOF
                run_or_die 1 "NORDIC" bash -c \
                    "matlab -nosplash -batch \"run('${TMP_M}');\" && rm -f '${TMP_M}'"
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
            # Verify output was actually created (AS2 can exit 0 on mcflirt failure)
            if [[ ! -f "${PREPROC_DIR}/mc/${mc_file}_mcf.nii.gz" ]]; then
                echo "  ERROR: Step 2 — mcf output missing despite exit 0. Check AS2 logs."
                echo "         Rerun with RESTART_FROM_STEP=2"
                rm -f "$(_ckpt_dir)/step_2.done"
                exit 1
            fi
        fi

        # -------------------------------------------------------
        # STEP 3: Unwarping  /  mean functional (no fmap)
        # -------------------------------------------------------
        if step_done 3; then
            echo "  Step 3: Unwarping/mean func [SKIP]"
        else
            if [ -n "${FMAP_DIR}" ]; then
                echo "  Step 3: Unwarping (fmap: ${FMAP_DIR})..."
                run_or_die 3 "Unwarping" \
                    bash ${sDIR}AS3_unwarping.sh
            else
                echo "  Step 3: No fmap — computing mean functional..."
                run_or_die 3 "Mean functional" bash -c "
                    fslmaths ${PREPROC_DIR}/mc/${mc_file}_mcf.nii.gz \
                              -Tmean ${PREPROC_DIR}/mc/meanFunctional_${RUN_NAME}.nii.gz \
                    && gunzip -c ${PREPROC_DIR}/mc/meanFunctional_${RUN_NAME}.nii.gz \
                             > ${PREPROC_DIR}/FIACH/meanFunctional_${RUN_NAME}.nii \
                    && gunzip -c ${PREPROC_DIR}/mc/${mc_file}_mcf.nii.gz \
                             > ${PREPROC_DIR}/FIACH/${mc_file}_mcf.nii
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
        # T1 is shared across caps — skip extraction if already done,
        # but always re-register mask to EPI space for this run.
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
                gunzip -c '${T1_SRC}' > '${T1_DIR}/UNI_T1.nii' \
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

                BOLD_JSON="${BOLD_SRC%.nii.gz}.json"
                if [[ ! -f "$BOLD_JSON" ]]; then
                    echo "  ERROR: No JSON sidecar found at ${BOLD_JSON}"
                    exit 1
                fi
                export BOLD_JSON

                MEAN_SRC="${PREPROC_DIR}/mc/meanFunctional_${RUN_NAME}.nii.gz"
                [[ ! -f "$MEAN_SRC" ]] && \
                    MEAN_SRC="${PREPROC_DIR}/mc/meanFunctional.nii.gz"
                run_or_die 6 "FIACH" bash -c "
                    gunzip -c '${MEAN_SRC}' \
                        > ${PREPROC_DIR}/FIACH/meanFunctional.nii \
                    && bash ${sDIR}AS6_call_FIACH.sh
                "

                RCLEAN="${PREPROC_DIR}/FIACH/rclean_${fiach_file}.nii"
                if [[ ! -f "$RCLEAN" ]]; then
                    echo "  ERROR: Step 6 — rclean_${fiach_file}.nii not produced."
                    echo "         Check MATLAB output above. Rerun with RESTART_FROM_STEP=6"
                    rm -f "$(_ckpt_dir)/step_6.done"
                    exit 1
                fi
            fi

            if step_done 7; then
                echo "  Step 7: Combine regressors [SKIP]"
            else
                echo "  Step 7: Combine motion + FIACH regressors..."
                MOTION_PAR="${PREPROC_DIR}/mc/${mc_file}_mcf.par"
                export MOTION_PAR
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

        # --- Export pipeline variables on run completion ---
        ENV_FILE="${DIR}derivatives/${SUB}/stats/pipeline_vars_${RUN_LABEL}.env"
        {
            echo "SUB=${SUB}"
            echo "DIR=${DIR}"
            echo "CAP_NAME=${CAP_NAME}"
            echo "RUN_NAME=${RUN_NAME}"
            echo "RUN_LABEL=${RUN_LABEL}"
            echo "BOLD_SRC=${BOLD_SRC}"
            echo "FMAP_DIR=${FMAP_DIR}"
            echo "PREPROC_DIR=${PREPROC_DIR}"
            echo "T1_DIR=${T1_DIR}"
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