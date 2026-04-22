#!/bin/bash
# ============================================================
# AS3_unwarping.sh
# GRE fieldmap-based EPI unwarping using FSL.
# Expects env vars: SUB, RUN_NAME, mc_file, BOLD_JSON,
#                   PREPROC_DIR, FMAP_DIR
# ============================================================

extDIR=$(cat 1_directory.txt)

if [ -z "${SUB}" ];         then echo "ERROR: SUB not defined.";         exit 1; fi
if [ -z "${mc_file}" ];     then echo "ERROR: mc_file not defined.";     exit 1; fi
if [ -z "${PREPROC_DIR}" ]; then echo "ERROR: PREPROC_DIR not defined."; exit 1; fi
if [ -z "${FMAP_DIR}" ] || [ ! -d "${FMAP_DIR}" ]; then
    echo "ERROR: FMAP_DIR not set or does not exist: ${FMAP_DIR}"; exit 1
fi

echo "  Using fmap directory: ${FMAP_DIR}"

MC_DIR="${PREPROC_DIR}/mc/"
FMAP_OUT="${PREPROC_DIR}/fmap/"
FIACH_DIR="${PREPROC_DIR}/FIACH/"
mkdir -p "${FMAP_OUT}"

# --- Find fieldmap files ---
MAGN=$(ls "${FMAP_DIR}"*_e1.nii.gz 2>/dev/null | head -n 1)
PHASE=$(ls "${FMAP_DIR}"*_e2_ph.nii.gz 2>/dev/null | head -n 1)

if [ -z "${MAGN}" ];  then echo "ERROR: No magnitude (*_e1.nii.gz) in ${FMAP_DIR}";    exit 1; fi
if [ -z "${PHASE}" ]; then echo "ERROR: No phase diff (*_e2_ph.nii.gz) in ${FMAP_DIR}"; exit 1; fi

echo "  Magnitude : ${MAGN}"
echo "  Phase diff: ${PHASE}"

# --- Read dTE from JSON ---
dTE=""
FMAP_JSON=$(ls "${FMAP_DIR}"*.json 2>/dev/null | head -n 1)
if [ -n "${FMAP_JSON}" ]; then
    TE1=$(jq -r '.EchoTime1 // empty' "${FMAP_JSON}" 2>/dev/null)
    TE2=$(jq -r '.EchoTime2 // empty' "${FMAP_JSON}" 2>/dev/null)
    if [ -n "${TE1}" ] && [ -n "${TE2}" ]; then
        dTE=$(echo "scale=4; (${TE2} - ${TE1}) * 1000" | bc)
        echo "  dTE from fmap JSON: ${dTE} ms"
    fi
fi
if [ -z "${dTE}" ]; then
    MAGN_JSON="${MAGN%.nii.gz}.json"
    if [ -f "${MAGN_JSON}" ]; then
        dTE_s=$(jq -r '.EchoTimeDifference // empty' "${MAGN_JSON}" 2>/dev/null)
        if [ -n "${dTE_s}" ]; then
            dTE=$(echo "scale=4; ${dTE_s} * 1000" | bc)
            echo "  dTE from magnitude JSON: ${dTE} ms"
        fi
    fi
fi
if [ -z "${dTE}" ]; then
    dTE=2.46
    echo "  WARNING: Could not read dTE — using default ${dTE} ms"
fi

# --- Brain extract magnitude ---
echo "  Brain extracting magnitude..."
MAGN_BRAIN="${FMAP_OUT}magnitude_brain"
bet "${MAGN}" "${MAGN_BRAIN}" -f 0.5 -g 0 -m

# --- Prepare fieldmap ---
echo "  Preparing fieldmap (dTE=${dTE} ms)..."
FIELDMAP="${FMAP_OUT}fieldmap_rads"
fsl_prepare_fieldmap SIEMENS "${PHASE}" "${MAGN_BRAIN}" "${FIELDMAP}" "${dTE}"

# --- Read EPI params ---
EPI_TE=""
DWELL_TIME=""
if [ -n "${BOLD_JSON}" ] && [ -f "${BOLD_JSON}" ]; then
    EPI_TE=$(jq -r '.EchoTime // empty'                               "${BOLD_JSON}" 2>/dev/null)
    DWELL_TIME=$(jq -r '.DwellTime // .EffectiveEchoSpacing // empty' "${BOLD_JSON}" 2>/dev/null)
fi
if [ -z "${EPI_TE}" ];    then EPI_TE=0.024;    echo "  WARNING: Using default EPI TE=${EPI_TE}s"; fi
if [ -z "${DWELL_TIME}" ]; then DWELL_TIME=0.000395; echo "  WARNING: Using default dwell=${DWELL_TIME}s"; fi

# --- Unwarp ---
INPUT_EPI="${MC_DIR}${mc_file}_mcf.nii.gz"
OUTPUT_EPI="${MC_DIR}${mc_file}_mcf_unwarp.nii.gz"
if [ ! -f "${INPUT_EPI}" ]; then echo "ERROR: EPI not found: ${INPUT_EPI}"; exit 1; fi

echo "  Unwarping EPI..."
fugue -i "${INPUT_EPI}" \
      --loadfmap="${FIELDMAP}" \
      --dwell="${DWELL_TIME}" \
      --unwarpdir=y- \
      -u "${OUTPUT_EPI}"

echo "  Unwarped EPI saved: ${OUTPUT_EPI}"

# --- Compute mean functional ---
MEAN_OUT="${MC_DIR}meanFunctional_${RUN_NAME}.nii.gz"
fslmaths "${OUTPUT_EPI}" -Tmean "${MEAN_OUT}"
gunzip -c "${MEAN_OUT}"       > "${FIACH_DIR}meanFunctional_${RUN_NAME}.nii"
gunzip -c "${OUTPUT_EPI}"     > "${FIACH_DIR}${mc_file}_mcf_unwarp.nii"
echo "  Mean functional saved: ${MEAN_OUT}"
echo "  Unwarping complete for ${SUB} / ${RUN_NAME}"