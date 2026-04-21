#!/bin/bash
HPF=false
REGRESS=false

extDIR=$(cat 1_directory.txt)
sDIR="$(dirname $(realpath $0))/"

if [ -z "${SUB}" ];         then echo "ERROR: SUB not defined.";         exit 1; fi
if [ -z "${fiach_file}" ];  then echo "ERROR: fiach_file not defined.";  exit 1; fi
if [ -z "${PREPROC_DIR}" ]; then echo "ERROR: PREPROC_DIR not defined."; exit 1; fi

# --- Resolve JSON sidecar ---
if [ -n "${BOLD_JSON}" ] && [ -f "${BOLD_JSON}" ]; then
    JSON="${BOLD_JSON}"
else
    echo "WARNING: BOLD_JSON not set, falling back to glob (may be ambiguous)"
    JSON=$(ls ${extDIR}${SUB}/func/*bold.json 2>/dev/null | head -n 1)
    if [ -z "${JSON}" ]; then
        echo "ERROR: No bold.json sidecar found for ${SUB}"
        exit 1
    fi
fi
echo "Using JSON: ${JSON}"

TR=$(jq -r '.RepetitionTime' "${JSON}")
TE=$(jq -r '.EchoTime'       "${JSON}")
if [ "${TR}" = "null" ] || [ -z "${TR}" ]; then echo "ERROR: No RepetitionTime in ${JSON}"; exit 1; fi
if [ "${TE}" = "null" ] || [ -z "${TE}" ]; then echo "ERROR: No EchoTime in ${JSON}";       exit 1; fi

echo "TR: ${TR}s  TE: ${TE}s"
B0=7

cp ${sDIR}run_fiach_DC.m ${PREPROC_DIR}/FIACH/run_fiach.m

FIACH_DIR="${PREPROC_DIR}/FIACH"
TMP_M="${FIACH_DIR}/run_fiach_call_${RUN_NAME}.m"

cat > "${TMP_M}" << MATLAB_EOF
clear; clc;
cfg               = struct();
cfg.TR            = ${TR};
cfg.TE            = ${TE};
cfg.B0            = ${B0};
cfg.sName         = '${SUB}';
cfg.maxPCs        = 6;
cfg.verbose       = 1;
cfg.debug         = true;
cfg.do_hpf        = ${HPF};
cfg.do_regression = ${REGRESS};
cd('${FIACH_DIR}');
run_fiach('${fiach_file}.nii', 'meanFunctional.nii', 'rfBrainMask.nii', cfg);
MATLAB_EOF

echo "Running MATLAB script: ${TMP_M}"
matlab -nosplash -batch "run('${TMP_M}');"
MATLAB_EXIT=$?

if [ ${MATLAB_EXIT} -ne 0 ]; then
    echo "ERROR: MATLAB exited with code ${MATLAB_EXIT} during FIACH"
    exit 1
fi

rm -f "${TMP_M}"