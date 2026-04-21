#!/bin/bash
export FSLDIR=$HOME/fsl
source $FSLDIR/etc/fslconf/fsl.sh
export PATH=$FSLDIR/bin:$PATH

extDIR=$(cat 1_directory.txt)

# SUB is exported from the wrapper
if [ -z "${SUB}" ]; then
    echo "ERROR: SUB not defined. Please export SUB from the wrapper."
    exit 1
fi

OUTDIR="${extDIR}derivatives/${SUB}/preproc/mc/"
DIR="${extDIR}${SUB}/fmap/"
EPI_DIR="${extDIR}${SUB}/func/"
MAG=$(find ${DIR} -name "*e1.nii.gz" | head -1)
MAG2=$(find ${DIR} -name "*e2.nii.gz" | head -1)
PHASE=$(find ${DIR} -name "*ph.nii.gz" | head -1)

EPI="${OUTDIR}${mc_file}_mcf.nii.gz"
EPI_MEAN=${OUTDIR}mean_epi_fmap.nii.gz
fslmaths ${EPI} -Tmean ${EPI_MEAN}

FMAP1_JSON=$(find ${DIR} -name "*e1*.json" | head -1)
FMAP2_JSON=$(find ${DIR} -name "*e2*.json" | head -1)
EPI_JSON=$(find ${EPI_DIR} -name "*bold*.json" | head -1)

DTE=$(python3 -c "
import json
with open('${FMAP1_JSON}') as f:
    d = json.load(f)
te1 = d['EchoTime']
with open('${FMAP2_JSON}') as f:
    d = json.load(f)
te2 = d['EchoTime']
print(round(te2 - te1, 5))
")

DWELL=$(python3 -c "
import json
with open('${EPI_JSON}') as f:
    d = json.load(f)
print(d['EffectiveEchoSpacing'])
")

READOUT=$(python3 -c "
import json
with open('${EPI_JSON}') as f:
    d = json.load(f)
print(d['TotalReadoutTime'])
")

PE_DIR=$(python3 -c "
import json
with open('${EPI_JSON}') as f:
    d = json.load(f)
print(d['PhaseEncodingDirection'])
")

if [ "${PE_DIR}" == "j-" ]; then
    FSL_PE_DIR="y-"
elif [ "${PE_DIR}" == "j" ]; then
    FSL_PE_DIR="y"
elif [ "${PE_DIR}" == "i-" ]; then
    FSL_PE_DIR="x-"
elif [ "${PE_DIR}" == "i" ]; then
    FSL_PE_DIR="x"
fi

echo "dTE: ${DTE}"
echo "Dwell: ${DWELL}"
echo "Readout: ${READOUT}"
echo "PE dir: ${PE_DIR}"
echo "FSL PE dir: ${FSL_PE_DIR}"

# 1. Average magnitude, brain extract
echo 'Average magnitude, brain extract...'
fslmaths ${MAG} -add ${MAG2} -div 2 ${OUTDIR}mag_avg.nii.gz
bet ${OUTDIR}mag_avg.nii.gz ${OUTDIR}mag_brain.nii.gz -f 0.4 -m
fslmaths ${OUTDIR}mag_brain.nii.gz -bin ${OUTDIR}mag_mask.nii.gz

# 2. Rescale phase to radians, unwrap
echo 'Rescaling to radians...'
fslmaths ${PHASE} -mul 0.000766990393 ${OUTDIR}phase_rad.nii.gz
prelude -a ${OUTDIR}mag_brain.nii.gz \
        -p ${OUTDIR}phase_rad.nii.gz \
        -m ${OUTDIR}mag_mask.nii.gz \
        -o ${OUTDIR}phase_unwrapped.nii.gz -v

# 3. Phase (rad) to rad/s
fslmaths ${OUTDIR}phase_unwrapped.nii.gz \
    -div ${DTE} \
    ${OUTDIR}fieldmap_rads.nii.gz

# 4. Smooth and mask
echo 'Smoothing and masking of B0...'
fugue --loadfmap=${OUTDIR}fieldmap_rads.nii.gz \
      --mask=${OUTDIR}mag_mask.nii.gz \
      --savefmap=${OUTDIR}fieldmap_rads_smooth.nii.gz \
      --smooth3=2

# 5. Register fieldmap to EPI
echo 'Registering B0 to EPI...'
flirt -in ${OUTDIR}mag_brain.nii.gz \
      -ref ${EPI_MEAN} \
      -out ${OUTDIR}mag2epi.nii.gz \
      -omat ${OUTDIR}mag2epi.mat \
      -dof 6 \
      -cost corratio

flirt -in ${OUTDIR}fieldmap_rads_smooth.nii.gz \
      -ref ${EPI_MEAN} \
      -out ${OUTDIR}fieldmap_rads_epi.nii.gz \
      -init ${OUTDIR}mag2epi.mat \
      -applyxfm

# 6. Apply unwarping
echo 'Applying unwarping...'
fugue -i ${EPI} \
      --dwell=${DWELL} \
      --loadfmap=${OUTDIR}fieldmap_rads_epi.nii.gz \
      --unwarpdir=${FSL_PE_DIR} \
      -u ${OUTDIR}${mc_file}_mcf_unwarp.nii.gz

echo "Done — unwarped EPI: ${OUTDIR}${mc_file}_mcf_unwarp.nii.gz"

echo 'Create meanFunc from unwarped EPI...'
EPI_MEAN_UN=${OUTDIR}meanFunctional.nii.gz
fslmaths ${OUTDIR}${mc_file}_mcf_unwarp.nii.gz -Tmean ${EPI_MEAN_UN}

gunzip -c ${OUTDIR}meanFunctional.nii.gz > ${extDIR}derivatives/${SUB}/preproc/FIACH/meanFunctional.nii
echo 'Step 3 complete'