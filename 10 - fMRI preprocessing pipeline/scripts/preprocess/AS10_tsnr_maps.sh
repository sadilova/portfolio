#!/bin/bash
extDIR=$(cat 1_directory.txt)

if [ -z "${SUB}" ]; then
    echo "ERROR: SUB not defined. Please export SUB from the wrapper."
    exit 1
fi

if [ -z "${RUN_LABEL}" ]; then
    echo "ERROR: RUN_LABEL not defined. Please export RUN_LABEL from the wrapper."
    exit 1
fi

DIR=${extDIR}derivatives/${SUB}/preproc/

# --- Input files for tSNR (skip if not found) ---
# Uses pipeline env vars exported by the wrapper so filenames are always consistent
files=(
    "${DIR}NORDIC/NORDIC_Run_BOLD_${SUB}_${RUN_LABEL}.nii"
    "${DIR}mc/${mc_file}_mcf.nii.gz"
    "${DIR}FIACH/${fiach_file}.nii"
    "${DIR}FIACH/${reg_file}.nii"
    "${DIR}reg/reg_${reg_file}.nii.gz"
    "${DIR}reg/norm_${reg_file}.nii"
    "${DIR}smooth/${smooth_file}_smooth.nii.gz"
)

# --- Masks ---
mask_epi="${DIR}FIACH/rfBrainMask.nii"
mask_t1="${DIR}FIACH/Masked_UNI.nii"
mask_mni="/home/asa25/fsl/data/standard/MNI152_T1_1mm_brain_mask.nii.gz"

mkdir -p "${DIR}tsnr"

echo "Computing tSNR maps for ${SUB} / ${RUN_LABEL}:"

for file in "${files[@]}"; do
    # Skip missing files silently (not all steps may have run)
    if [ ! -f "$file" ]; then
        echo "  [SKIP] Not found: $file"
        continue
    fi

    base=$(basename "$file" .nii.gz)
    base=$(basename "$base" .nii)

    echo "  Computing tSNR for: ${base}"

    mean="${DIR}tsnr/${base}_mean.nii.gz"
    std="${DIR}tsnr/${base}_std.nii.gz"
    tsnr="${DIR}tsnr/${base}_tsnr.nii.gz"

    # Select mask based on space
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