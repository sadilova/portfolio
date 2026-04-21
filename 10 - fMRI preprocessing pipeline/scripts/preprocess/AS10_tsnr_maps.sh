#!/bin/bash
extDIR=$(cat 1_directory.txt)

if [ -z "${SUB}" ];         then echo "ERROR: SUB not defined.";         exit 1; fi
if [ -z "${RUN_NAME}" ];    then echo "ERROR: RUN_NAME not defined.";    exit 1; fi
if [ -z "${PREPROC_DIR}" ]; then echo "ERROR: PREPROC_DIR not defined."; exit 1; fi

# --- Input files for tSNR ---
files=(
    "${PREPROC_DIR}/NORDIC/NORDIC_Run_BOLD_${SUB}_${RUN_NAME}.nii"
    "${PREPROC_DIR}/mc/${mc_file}_mcf.nii.gz"
    "${PREPROC_DIR}/FIACH/${reg_file}.nii"
    "${PREPROC_DIR}/reg/reg_${reg_file}.nii.gz"
    "${PREPROC_DIR}/reg/norm_${reg_file}.nii"
    "${PREPROC_DIR}/smooth/${smooth_file}_smooth.nii.gz"
)

# --- Masks ---
mask_epi="${PREPROC_DIR}/FIACH/rfBrainMask.nii"
mask_t1="${extDIR}derivatives/${SUB}/preproc/T1/Masked_UNI.nii"
mask_mni="/home/asa25/fsl/data/standard/MNI152_T1_1mm_brain_mask.nii.gz"

mkdir -p "${PREPROC_DIR}/tsnr"

echo "Computing tSNR maps for ${SUB} / ${RUN_LABEL}:"

for file in "${files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  [SKIP] Not found: $file"
        continue
    fi

    base=$(basename "$file" .nii.gz)
    base=$(basename "$base" .nii)
    echo "  Computing tSNR for: ${base}"

    mean="${PREPROC_DIR}/tsnr/${base}_mean.nii.gz"
    std="${PREPROC_DIR}/tsnr/${base}_std.nii.gz"
    tsnr="${PREPROC_DIR}/tsnr/${base}_tsnr.nii.gz"

    # Select mask based on image space
    if [[ "$file" == *"norm_"* ]]; then
        mask="$mask_mni"
    elif [[ "$file" == *"/reg/"* ]] || [[ "$file" == *"/smooth/"* ]]; then
        mask="$mask_t1"
    else
        mask="$mask_epi"
    fi

    fslmaths "$file" -mas "$mask" -Tmean "$mean" \
        && fslmaths "$file" -mas "$mask" -Tstd  "$std" \
        && fslmaths "$mean" -div "$std" "$tsnr" \
        && echo "    Saved: $tsnr" \
        || echo "    WARNING: tSNR failed for ${base}"
done

echo "tSNR complete for ${SUB} / ${RUN_LABEL}"