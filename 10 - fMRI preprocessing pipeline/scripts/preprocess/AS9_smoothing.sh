#!/bin/bash
extDIR=$(cat 1_directory.txt)

if [ -z "${SUB}" ]; then
    echo "ERROR: SUB not defined. Please export SUB from the wrapper."
    exit 1
fi

if [ -z "${smooth_file}" ]; then
    echo "ERROR: smooth_file not defined. Please export smooth_file from the wrapper."
    exit 1
fi

DIR="${extDIR}derivatives/${SUB}/preproc/reg/"
OUTDIR="${extDIR}derivatives/${SUB}/preproc/smooth/"
sigma=$(echo "scale=6; 3 / 2.3548" | bc)

# Input may be .nii or .nii.gz — check which exists
INPUT_NII="${DIR}${smooth_file}.nii"
INPUT_NIIGZ="${DIR}${smooth_file}.nii.gz"

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
fslmaths ${INPUT} -s ${sigma} ${OUTDIR}${smooth_file}_smooth.nii.gz