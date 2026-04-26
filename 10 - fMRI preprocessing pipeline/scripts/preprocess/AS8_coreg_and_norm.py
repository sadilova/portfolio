import ants
import nibabel as nib
import numpy as np
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from nitransforms.linear import Affine as NiAffine
from nitransforms.io.fsl import FSLLinearTransform

DIR         = Path('1_directory.txt').read_text().strip()
SUB         = os.environ.get('SUB')
RUN_NAME    = os.environ.get('RUN_NAME')
PREPROC_DIR = os.environ.get('PREPROC_DIR')
T1_DIR      = os.environ.get('T1_DIR')
REG_FILE    = os.environ.get('reg_file')
FSLDIR      = os.environ.get('FSLDIR', os.path.expanduser('~/fsl'))

if not SUB:         raise ValueError("SUB not defined.")
if not RUN_NAME:    raise ValueError("RUN_NAME not defined.")
if not PREPROC_DIR: raise ValueError("PREPROC_DIR not defined.")
if not T1_DIR:      raise ValueError("T1_DIR not defined.")
if not REG_FILE:    raise ValueError("reg_file not defined.")

CHUNK   = 50
reg_dir = f'{PREPROC_DIR}/reg'
os.makedirs(reg_dir, exist_ok=True)

# --- Paths ---
t1_path       = f'{T1_DIR}/Masked_UNI.nii'
wm_mask       = f'{T1_DIR}/synthseg/WM_mask.nii.gz'
func_path     = f'{PREPROC_DIR}/FIACH/{REG_FILE}.nii'
reg_out       = f'{PREPROC_DIR}/reg/reg_{REG_FILE}.nii.gz'
norm_out      = f'{PREPROC_DIR}/reg/norm_{REG_FILE}.nii'
init_mat      = f'{reg_dir}/init_{RUN_NAME}.mat'
bbr_mat       = f'{reg_dir}/bbr_{RUN_NAME}.mat'
bbr_mat_ants  = f'{reg_dir}/bbr_{RUN_NAME}_ants.mat'
mni_path      = f'{FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz'  # brain-extracted
mni_warp      = f'{T1_DIR}/t1_to_mni_warp.nii.gz'                     # shared across runs
mni_affine    = f'{T1_DIR}/t1_to_mni_affine.mat'                       # shared across runs

# Mean functional: prefer run-specific, fall back to generic
meanfunc_path = f'{PREPROC_DIR}/mc/meanFunctional_{RUN_NAME}.nii.gz'
if not os.path.isfile(meanfunc_path):
    fb = f'{PREPROC_DIR}/mc/meanFunctional.nii.gz'
    if os.path.isfile(fb):
        print(f'Using fallback mean functional: {fb}')
        meanfunc_path = fb
    else:
        raise FileNotFoundError(f'Mean functional not found at:\n  {meanfunc_path}\n  {fb}')

print(f'Using mean functional: {meanfunc_path}')


def run(cmd, label):
    print(f'  [{label}] {cmd}')
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stdout: print(result.stdout)
    if result.stderr: print(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f'{label} failed (exit {result.returncode})')


# ============================================================
# STEP 1: Check SynthSeg WM mask exists
# ============================================================
if not os.path.isfile(wm_mask):
    raise FileNotFoundError(
        f'WM mask not found: {wm_mask}\n'
        f'Check that Step 5 (SynthSeg) completed successfully.')
print(f'Using SynthSeg WM mask: {wm_mask}')

# ============================================================
# STEP 2: Initial rigid registration (EPI -> T1, 6 DOF)
# ============================================================
print('Initial rigid registration (EPI -> T1)...')
run(f'flirt -in {meanfunc_path} -ref {t1_path} '
    f'-out {reg_dir}/init_meanfunc_{RUN_NAME} -omat {init_mat} -dof 6',
    'FLIRT init')

# ============================================================
# STEP 3: BBR refinement using SynthSeg WM mask
# ============================================================
print('BBR registration (EPI -> T1)...')
run(f'flirt -in {meanfunc_path} -ref {t1_path} '
    f'-out {reg_dir}/bbr_meanfunc_{RUN_NAME} -omat {bbr_mat} '
    f'-wmseg {wm_mask} -cost bbr -init {init_mat} -dof 6',
    'FLIRT BBR')

# ============================================================
# STEP 4: Convert FSL BBR mat to ITK format using nitransforms
# ============================================================
print('Converting FSL BBR mat to ITK format (nitransforms)...')
fsl_xfm = FSLLinearTransform.from_filename(bbr_mat)
mat = fsl_xfm.to_ras(
    reference=nib.load(t1_path),
    moving=nib.load(meanfunc_path)
)
itk_xfm = NiAffine(mat)
itk_xfm.to_filename(bbr_mat_ants, fmt='itk')
print(f'ITK mat saved: {bbr_mat_ants}')

# ============================================================
# STEP 5: T1 -> MNI nonlinear (ANTs SyN)
#   Saved to T1_DIR — reused across all runs/caps for this subject
# ============================================================
img_t1 = ants.image_read(t1_path)
mni    = ants.image_read(mni_path)

if os.path.isfile(mni_warp):
    print(f'T1->MNI warp already exists, reusing: {mni_warp}')
else:
    print('Registering T1 to MNI (ANTs SyN)...')
    reg_t1_mni = ants.registration(
        fixed=mni,
        moving=img_t1,
        type_of_transform='SyN',
        verbose=True
    )
    shutil.copy(reg_t1_mni['fwdtransforms'][0], mni_warp)
    shutil.copy(reg_t1_mni['fwdtransforms'][1], mni_affine)
    print(f'T1->MNI warp saved: {mni_warp}')

# ============================================================
# STEP 6: Apply transforms to 4D in chunks
#   reg:  BBR mat only             -> T1 space
#   norm: BBR mat + ANTs SyN warp  -> MNI space (single interpolation)
# ============================================================
func_nib    = nib.load(func_path)
arr_4d      = func_nib.get_fdata(dtype=np.float32)
n_vols      = arr_4d.shape[-1]
ref_t1      = ants.image_read(t1_path)
ref_mni     = ants.image_read(mni_path)
result_reg  = None
result_norm = None

print(f'Applying transforms in chunks of {CHUNK} (total {n_vols} volumes)...')

with tempfile.TemporaryDirectory() as tmpdir:
    for start in range(0, n_vols, CHUNK):
        end = min(start + CHUNK, n_vols)
        print(f'  Volumes {start+1}–{end}...')

        chunk_path = f'{tmpdir}/chunk.nii.gz'
        nib.save(nib.Nifti1Image(arr_4d[..., start:end], func_nib.affine), chunk_path)
        chunk_ants = ants.image_read(chunk_path)

        # EPI -> T1 (BBR mat only)
        chunk_t1 = ants.apply_transforms(
            fixed=ref_t1, moving=chunk_ants,
            transformlist=[bbr_mat_ants],
            interpolator='bSpline',
            imagetype=3
        )
        t1_data = chunk_t1.numpy()
        if result_reg is None:
            result_reg = np.zeros((*t1_data.shape[:3], n_vols), dtype=np.float32)
        result_reg[..., start:end] = t1_data

        # EPI -> MNI (BBR mat + ANTs SyN warp, single interpolation)
        # Transform order: last applied first
        chunk_mni = ants.apply_transforms(
            fixed=ref_mni, moving=chunk_ants,
            transformlist=[mni_warp, mni_affine, bbr_mat_ants],
            interpolator='bSpline',
            imagetype=3
        )
        mni_data = chunk_mni.numpy()
        if result_norm is None:
            result_norm = np.zeros((*mni_data.shape[:3], n_vols), dtype=np.float32)
        result_norm[..., start:end] = mni_data

# ============================================================
# STEP 7: Save outputs
# ============================================================
print('Saving registered (T1 space)...')
nib.save(nib.Nifti1Image(result_reg, nib.load(t1_path).affine), reg_out)
print(f'  reg saved:  {reg_out}')

print('Saving normalised (MNI space)...')
nib.save(nib.Nifti1Image(result_norm, nib.load(mni_path).affine), norm_out)
print(f'  norm saved: {norm_out}')