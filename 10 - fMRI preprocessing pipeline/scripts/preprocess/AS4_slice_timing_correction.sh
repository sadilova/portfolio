#!/bin/bash
# ============================================================
# AS4_slice_timing_correction.sh
# Slice timing correction using 3dTshift (AFNI)
# ============================================================
extDIR=$(cat 1_directory.txt)

if [ -z "${SUB}" ]; then
    echo "ERROR: SUB not defined. Please export SUB from the wrapper."
    exit 1
fi
if [ -z "${PREPROC_DIR}" ]; then
    echo "ERROR: PREPROC_DIR not defined. Please export from the wrapper."
    exit 1
fi

INPUT="${PREPROC_DIR}/mc/${sc_file}.nii"
OUTPUT="${PREPROC_DIR}/slicecor/sc${sc_file}.nii.gz"

# Use run-specific JSON from wrapper; fallback to glob
if [ -n "${BOLD_JSON}" ] && [ -f "${BOLD_JSON}" ]; then
    JSON="${BOLD_JSON}"
else
    echo "WARNING: BOLD_JSON not set, falling back to glob (may be ambiguous)"
    JSON=$(ls ${extDIR}${SUB}/func/*bold.json 2>/dev/null | head -n 1)
    if [ -z "${JSON}" ]; then
        echo "ERROR: No bold.json found for ${SUB}"
        exit 1
    fi
fi

# --- Extract TR from JSON ---
TR=$(jq -r '.RepetitionTime' ${JSON})
if [ "${TR}" = "null" ] || [ -z "${TR}" ]; then
    echo "ERROR: No RepetitionTime found in ${JSON}"
    exit 1
fi

echo "TR: ${TR}s"
echo "Input:  ${INPUT}"
echo "Output: ${OUTPUT}"

if jq -e '.SliceTiming' ${JSON} > /dev/null 2>&1; then
    echo "Slice timing found in JSON..."
    jq -r '.SliceTiming[]' ${JSON} > ${PREPROC_DIR}/slicecor/slice_timing.txt
    3dTshift -prefix ${OUTPUT} \
             -tpattern @${PREPROC_DIR}/slicecor/slice_timing.txt \
             -TR ${TR} ${INPUT}
else
    echo "No SliceTiming field found in JSON, do you want to proceed without it? (y/n)"
    read -t 30 answer
    if [ "$answer" = "y" ]; then
        echo "Proceeding without slice timing correction..."
        3dTshift -prefix ${OUTPUT} -TR ${TR} ${INPUT}
    else
        echo "Slice timing correction aborted."
        exit 1
    fi
fi

gunzip -c ${OUTPUT} > ${PREPROC_DIR}/FIACH/sc${sc_file}.nii
echo "Slice timing correction complete. Output: ${OUTPUT}"