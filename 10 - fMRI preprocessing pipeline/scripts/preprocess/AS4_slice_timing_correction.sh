#!/bin/bash
# ============================================================
# AS2_slice_timing_correction.sh
# Slice timing correction using 3dTshift (AFNI)
# ============================================================
extDIR=$(cat 1_directory.txt)
DIR=${extDIR}derivatives/${SUB}/preproc
# SUB is exported from the wrapper, no need to hardcode
if [ -z "${SUB}" ]; then
    echo "ERROR: SUB not defined. Please export SUB from the wrapper."
    exit 1
fi

INPUT="${DIR}/mc/${sc_file}.nii"
OUTPUT="${DIR}/slicecor/sc${sc_file}.nii.gz"
JSON=$(ls ${extDIR}${SUB}/func/*bold.json)

# --- Extract TR from JSON ---
TR=$(jq -r '.RepetitionTime' ${JSON})
if [ "${TR}" = "null" ] || [ -z "${TR}" ]; then
    echo "ERROR: No RepetitionTime found in JSON"
    exit 1
fi
echo "TR: ${TR}s"
echo "Input:  ${INPUT}"
echo "Output: ${OUTPUT}"

if jq -e '.SliceTiming' ${JSON} > /dev/null 2>&1; then
    echo "Slice timing found in JSON..."
    jq -r '.SliceTiming[]' ${JSON} > ${DIR}/slicecor/slice_timing.txt
    3dTshift -prefix ${OUTPUT} -tpattern @${DIR}/slicecor/slice_timing.txt -TR ${TR} ${INPUT}
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

gunzip -c ${OUTPUT} > ${extDIR}derivatives/${SUB}/preproc/FIACH/sc${sc_file}.nii
echo "Slice timing correction complete. Output: ${OUTPUT}"