#!/bin/bash
# ============================================================
# AS6_call_FIACH.sh
# Calls FIACH for a single run. Called from wrapper_preprocess.sh.
# Expects env vars: SUB, RUN_LABEL, fiach_file, mc_file, BOLD_JSON
# ============================================================

HPF=false
REGRESS=false

extDIR=$(cat 1_directory.txt)
DIR=${extDIR}derivatives/${SUB}/preproc/
sDIR="$(dirname $(realpath $0))/"

if [ -z "${SUB}" ]; then
    echo "ERROR: SUB not defined. Please export SUB from the wrapper."
    exit 1
fi

if [ -z "${fiach_file}" ]; then
    echo "ERROR: fiach_file not defined. Please export from the wrapper."
    exit 1
fi

if [ -z "${mc_file}" ]; then
    echo "ERROR: mc_file not defined. Please export from the wrapper."
    exit 1
fi

# --- Resolve JSON sidecar ---
# BOLD_JSON is set by the wrapper to exactly match the current run's sidecar.
# Fallback: try to find one in the func folder (warns if ambiguous).
if [ -n "${BOLD_JSON}" ] && [ -f "${BOLD_JSON}" ]; then
    JSON="${BOLD_JSON}"
else
    echo "WARNING: BOLD_JSON not set or not found, falling back to glob (may be ambiguous)"
    JSON=$(ls ${extDIR}${SUB}/func/*bold.json 2>/dev/null | head -n 1)
    if [ -z "${JSON}" ]; then
        echo "ERROR: No bold.json sidecar found for ${SUB} run ${RUN_LABEL}"
        exit 1
    fi
fi
echo "Using JSON: ${JSON}"

# --- Read scan parameters ---
TR=$(jq -r '.RepetitionTime' "${JSON}")
TE=$(jq -r '.EchoTime'       "${JSON}")

if [ "${TR}" = "null" ] || [ -z "${TR}" ]; then
    echo "ERROR: No RepetitionTime found in ${JSON}"
    exit 1
fi
if [ "${TE}" = "null" ] || [ -z "${TE}" ]; then
    echo "ERROR: No EchoTime found in ${JSON}"
    exit 1
fi

echo "TR: ${TR}s"
echo "TE: ${TE}s"

# B0 is scanner-specific; not usually in JSON
B0=7

# --- Copy FIACH script into working dir ---
cp ${sDIR}run_fiach_DC.m ${extDIR}derivatives/${SUB}/preproc/FIACH/run_fiach.m

# --- Write MATLAB commands to a temp script and run it ---
# Using a .m file avoids multiline -batch string issues.
FIACH_DIR="${DIR}FIACH"
TMP_M="${FIACH_DIR}/run_fiach_call_${RUN_LABEL}.m"

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

# Clean up temp script on success
rm -f "${TMP_M}"