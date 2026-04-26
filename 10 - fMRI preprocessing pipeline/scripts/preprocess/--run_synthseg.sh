#!/bin/bash

# SynthSeg segmentation + brain masking script
# Usage: ./run_synthseg.sh <subject_id> <path_to_T1>

set -e

SUBJECT_ID=$1
T1_INPUT=$2

# --- Config ---
SUBJECTS_DIR=${SUBJECTS_DIR:-/data/Annie/PROJECTS/EEGoddball_ERP_1/derivatives}
OUTPUT_DIR="${SUBJECTS_DIR}/${SUBJECT_ID}/synthseg"

# --- FreeSurfer setup ---
export FREESURFER_HOME=${FREESURFER_HOME:-/usr/local/freesurfer/8.2.0}
source "${FREESURFER_HOME}/SetUpFreeSurfer.sh"

# --- Checks ---
if [[ -z "$SUBJECT_ID" || -z "$T1_INPUT" ]]; then
    echo "Usage: $0 <subject_id> <path_to_T1>"
    exit 1
fi

if [[ ! -f "$T1_INPUT" ]]; then
    echo "Error: T1 not found at $T1_INPUT"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Running SynthSeg for subject: ${SUBJECT_ID}"
echo "Input:  ${T1_INPUT}"
echo "Output: ${OUTPUT_DIR}"

# --- Run SynthSeg segmentation ---
mri_synthseg \
    --i "$T1_INPUT" \
    --o "${OUTPUT_DIR}/synthseg.nii.gz" \
    --robust \
    --vol "${OUTPUT_DIR}/volumes.csv" \
    --qc  "${OUTPUT_DIR}/qc.csv" \
    --threads 8

# --- Derive brain mask from segmentation ---
echo "Generating brain mask..."
mri_binarize \
    --i "${OUTPUT_DIR}/synthseg.nii.gz" \
    --min 1 \
    --o "${OUTPUT_DIR}/brain_mask.nii.gz"

# --- Apply mask to T1 ---
echo "Applying brain mask to T1..."
mri_mask \
    "${T1_INPUT}" \
    "${OUTPUT_DIR}/brain_mask.nii.gz" \
    "${OUTPUT_DIR}/T1_masked.nii.gz"

echo ""
echo "Done. Outputs in ${OUTPUT_DIR}:"
echo "  synthseg.nii.gz   - full segmentation"
echo "  brain_mask.nii.gz - binary brain mask"
echo "  T1_masked.nii.gz  - skull-stripped T1"
echo "  volumes.csv       - structure volumes"
echo "  qc.csv            - QC scores"