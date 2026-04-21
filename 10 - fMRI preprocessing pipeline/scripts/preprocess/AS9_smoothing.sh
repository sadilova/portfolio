#!/bin/bash
extDIR=$(cat 1_directory.txt)

if [ -z "${SUB}" ];         then echo "ERROR: SUB not defined.";         exit 1; fi
if [ -z "${smooth_file}" ]; then echo "ERROR: smooth_file not defined."; exit 1; fi
if [ -z "${PREPROC_DIR}" ]; then echo "ERROR: PREPROC_DIR not defined."; exit 1; fi

sigma=$(echo "scale=6; 3 / 2.3548" | bc)

# Input may be .nii or .nii.gz
INPUT_NII="${PREPROC_DIR}/reg/${smooth_file}.nii"
INPUT_NIIGZ="${PREPROC_DIR}/reg/${smooth_file}.nii.gz"

if [ -f "${INPUT_NII}" ]; then
    INPUT="${INPUT_NII}"
elif [ -f "${INPUT_NIIGZ}" ]; then
    INPUT="${INPUT_NIIGZ}"
else
    echo "ERROR: Smoothing input not found at either:"
    echo "  ${INPUT_NII}"
    echo "  ${INPUT_NIIGZ}"
    exit 1
fi

echo "  Smoothing: ${INPUT}"
fslmaths "${INPUT}" -s ${sigma} "${PREPROC_DIR}/smooth/${smooth_file}_smooth.nii.gz"