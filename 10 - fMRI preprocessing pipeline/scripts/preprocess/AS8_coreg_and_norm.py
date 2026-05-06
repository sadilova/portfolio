import ants
import nibabel as nib
import numpy as np
import os
import shutil
import subprocess
from pathlib import Path
from nitransforms.linear import Affine
from nitransforms.nonlinear import DenseFieldTransform
from nitransforms.manip import TransformChain
from nitransforms.resampling import apply as nt_apply

DIR         = Path('1_directory.txt').read_text().strip()
SUB         = os.environ.get('SUB')
RUN_NAME    = os.environ.get('RUN_NAME')
PREPROC_DIR = os.environ.get('PREPROC_DIR')
T1_DIR      = os.environ.get('T1_DIR')
REG_FILE    = os.environ.get('reg_file')
FSLDIR      = os.environ.get('FSLDIR', os.path.expanduser('~/fsl'))
C3D         = os.environ.get('C3D', '/home/asa25/c3d-1.1.0-Linux-x86_64/bin/c3d_affine_tool')

if not SUB:         raise ValueError("SUB not defined.")
if not RUN_NAME:    raise ValueError("RUN_NAME not defined.")
if not PREPROC_DIR: raise ValueError("PREPROC_DIR not defined.")
if not T1_DIR:      raise ValueError("T1_DIR not defined.")
if not REG_FILE:    raise ValueError("reg_file not defined.")

reg_dir = f'{PREPROC_DIR}/reg'
os.makedirs(reg_dir, exist_ok=True)

t1_path       = f'{T1_DIR}/Masked_UNI.nii'
wm_mask       = f'{T1_DIR}/synthseg/WM_mask.nii.gz'
func_path     = f'{PREPROC_DIR}/FIACH/{REG_FILE}.nii'
reg_out       = f'{PREPROC_DIR}/reg/reg_{REG_FILE}.nii.gz'
norm_out      = f'{PREPROC_DIR}/reg/norm_{REG_FILE}.nii.gz'
init_mat      = f'{reg_dir}/init_{RUN_NAME}.mat'
bbr_mat       = f'{reg_dir}/bbr_{RUN_NAME}.mat'
bbr_mat_itk   = f'{reg_dir}/bbr_{RUN_NAME}.tfm'
mni_path      = f'{FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz'
mni_warp      = f'{T1_DIR}/t1_to_mni_warp.nii.gz'
mni_affine    = f'{T1_DIR}/t1_to_mni_affine.mat'

meanfunc_path = f'{PREPROC_DIR}/mc/meanFunctional_{RUN_NAME}.nii.gz'
if not os.path.isfile(meanfunc_path):
    raise FileNotFoundError(f'Mean functional not found at:\n  {meanfunc_path}')
print(f'Using mean functional: {meanfunc_path}')


def run(cmd, label):
    print(f'  [{label}] {cmd}')
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stdout: print(result.stdout)
    if result.stderr: print(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f'{label} failed (exit {result.returncode})')


# Step 1: Check SynthSeg WM mask
if not os.path.isfile(wm_mask):
    raise FileNotFoundError(
        f'WM mask not found: {wm_mask}\n'
        f'Check that Step 5 (SynthSeg) completed successfully.')
print(f'Using SynthSeg WM mask: {wm_mask}')

# Step 2: Initial rigid registration (EPI -> T1, 6 DOF)
print('Initial rigid registration (EPI -> T1)...')
run(f'flirt -in {meanfunc_path} -ref {t1_path} '
    f'-out {reg_dir}/init_meanfunc_{RUN_NAME} -omat {init_mat} -dof 6',
    'FLIRT init')

# Step 3: BBR refinement using SynthSeg WM mask
print('BBR registration (EPI -> T1)...')
run(f'flirt -in {meanfunc_path} -ref {t1_path} '
    f'-out {reg_dir}/bbr_meanfunc_{RUN_NAME} -omat {bbr_mat} '
    f'-wmseg {wm_mask} -cost bbr -init {init_mat} -dof 6',
    'FLIRT BBR')

# Step 4: Convert FSL BBR mat to ITK format
if not os.path.isfile(bbr_mat_itk):
    print('Converting FSL mat to ITK format (c3d)...')
    run(f'{C3D} -ref {t1_path} -src {meanfunc_path} '
        f'{bbr_mat} -fsl2ras -oitk {bbr_mat_itk}',
        'FSL->ITK (c3d)')
    print(f'  ITK mat saved: {bbr_mat_itk}')
else:
    print(f'ITK mat already exists, reusing: {bbr_mat_itk}')

# Step 5: T1 -> MNI nonlinear (ANTs SyN), reused across all runs
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

# Step 6: Load images and transforms
print('\nLoading images and transforms...')
func_nib    = nib.load(func_path)
t1_img      = nib.load(t1_path)
mni_img     = nib.load(mni_path)
arr_4d      = func_nib.get_fdata(dtype=np.float32)
n_vols      = arr_4d.shape[-1]
func_header = func_nib.header.copy()
print(f'  func shape: {func_nib.shape}')
print(f'  TR: {func_header.get_zooms()[3]:.3f}s')

bbr      = Affine.from_filename(bbr_mat_itk, fmt='itk')
syn_aff  = Affine.from_filename(mni_affine,  fmt='itk')
syn_warp = DenseFieldTransform(mni_warp, is_deltas=True)
chain    = TransformChain([bbr, syn_aff, syn_warp])
print('  transforms loaded OK')

# Step 7: Resample volume by volume
result_t1  = None
result_mni = None

print(f'\nTransforming {n_vols} volumes one by one...')
for i in range(n_vols):
    if i % 20 == 0:
        print(f'  Volume {i+1}/{n_vols}')

    vol_img = nib.Nifti1Image(arr_4d[..., i], func_nib.affine)

    warped_t1  = nt_apply(bbr,   vol_img, reference=t1_img).get_fdata(dtype=np.float32)
    warped_mni = nt_apply(chain, vol_img, reference=mni_img).get_fdata(dtype=np.float32)

    if result_t1 is None:
        result_t1  = np.zeros((*warped_t1.shape,  n_vols), dtype=np.float32)
        result_mni = np.zeros((*warped_mni.shape, n_vols), dtype=np.float32)

    result_t1[..., i]  = warped_t1
    result_mni[..., i] = warped_mni

# Step 8: Save outputs with header metadata preserved
print('\nSaving T1 space...')
out_t1 = nib.Nifti1Image(result_t1, t1_img.affine, header=func_header)
out_t1.set_data_dtype(np.float32)
nib.save(out_t1, reg_out)
print(f'  saved: {reg_out}')

print('Saving MNI space...')
out_mni = nib.Nifti1Image(result_mni, mni_img.affine, header=func_header)
out_mni.set_data_dtype(np.float32)
nib.save(out_mni, norm_out)
print(f'  saved: {norm_out}')

print('\nAS8 complete.')