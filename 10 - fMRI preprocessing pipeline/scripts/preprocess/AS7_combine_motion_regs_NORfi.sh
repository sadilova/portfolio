#!/bin/bash
extDIR=$(cat 1_directory.txt)
if [ -z "${SUB}" ]; then
    echo "ERROR: SUB not defined. Please export SUB from the wrapper."
    exit 1
fi
ROOT_DIR="${extDIR}derivatives/${SUB}/preproc"
N_PCS=6

# Derive motion file from mc_file (always <mc_file>_mcf.par, never sc prefix or double _mcf)
# mc_file is exported by the wrapper. MOTION_PAR may also be set there as a shortcut.
if [ -n "${MOTION_PAR}" ] && [ -f "${MOTION_PAR}" ]; then
    MOT_FILE="${MOTION_PAR}"
elif [ -n "${mc_file}" ]; then
    MOT_FILE="${ROOT_DIR}/mc/${mc_file}_mcf.par"
else
    echo "ERROR: Neither MOTION_PAR nor mc_file is defined. Please export from the wrapper."
    exit 1
fi

PC_FILE="${ROOT_DIR}/FIACH/noisyPCs_${fiach_file}.tsv"
OUT_FILE="${ROOT_DIR}/FIACH/multi_reg_FIACH_6PCs_${SUB}_${RUN_LABEL}.txt"

echo "Combining motion + FIACH (${N_PCS}PC)..."

# Check files exist
if [ ! -f "${MOT_FILE}" ]; then
    echo "ERROR: Motion file not found: ${MOT_FILE}"
    exit 1
fi
if [ ! -f "${PC_FILE}" ]; then
    echo "ERROR: PC file not found: ${PC_FILE}"
    exit 1
fi

# Get number of rows
MOT_ROWS=$(wc -l < "${MOT_FILE}")
PC_ROWS=$(wc -l < "${PC_FILE}")

# Sanity check row counts match
if [ "${MOT_ROWS}" -ne "${PC_ROWS}" ]; then
    echo "ERROR: Row mismatch (motion=${MOT_ROWS}, PCs=${PC_ROWS})"
    exit 1
fi

echo "  Rows: ${MOT_ROWS} | Motion cols: 6 | PCs used: ${N_PCS}"

# Combine motion (6 cols) + first 6 PCs
python3 -c "
import numpy as np
motion = np.loadtxt('${MOT_FILE}')
assert motion.shape[1] == 6, f'Expected 6 motion columns, got {motion.shape[1]}'
with open('${PC_FILE}') as f:
    lines = [l.strip() for l in f.readlines() if l.strip()]
pcs = np.array([
    [float(x) for x in line.split('\t') if x.strip()]
    for line in lines
])
assert pcs.shape[1] >= ${N_PCS}, f'Only {pcs.shape[1]} PCs available, need ${N_PCS}'
pcs = pcs[:, :${N_PCS}]
assert motion.shape[0] == pcs.shape[0], f'Row mismatch: motion={motion.shape[0]}, PCs={pcs.shape[0]}'
print(f'  Motion shape: {motion.shape}')
print(f'  PCs shape:    {pcs.shape}')
nuis = np.hstack([motion, pcs])
assert nuis.shape[1] == 12, f'Expected 12 columns, got {nuis.shape[1]}'
np.savetxt('${OUT_FILE}', nuis, delimiter='\t', fmt='%.6f')
print(f'  -> saved ${OUT_FILE} ({nuis.shape[0]} x {nuis.shape[1]})')
"

echo "Done — motion + FIACH (${N_PCS}PC) nuisance regressors for ${SUB}/${RUN_LABEL} saved."