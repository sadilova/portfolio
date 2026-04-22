import ants
import nibabel as nib
import numpy as np
import os
from scipy.ndimage import binary_fill_holes, binary_closing, binary_dilation
from nilearn.image import resample_to_img
from pathlib import Path

DIR         = Path('1_directory.txt').read_text().strip()
SUB         = os.environ.get('SUB')
RUN_NAME    = os.environ.get('RUN_NAME')
PREPROC_DIR = os.environ.get('PREPROC_DIR')
T1_DIR      = os.environ.get('T1_DIR')

if not SUB:         raise ValueError("SUB not defined.")
if not RUN_NAME:    raise ValueError("RUN_NAME not defined.")
if not PREPROC_DIR: raise ValueError("PREPROC_DIR not defined.")
if not T1_DIR:      raise ValueError("T1_DIR not defined.")

# --- Paths ---
t1_path          = f'{T1_DIR}/UNI_T1.nii'
brain_path_toreg = f'{T1_DIR}/Masked_UNI.nii'
synthseg_path    = f'{T1_DIR}/synthseg/synthseg.nii.gz'
brain_mask_path  = f'{T1_DIR}/synthseg/brain_mask.nii.gz'
wm_mask_path     = f'{T1_DIR}/synthseg/WM_mask.nii.gz'
mask_out_path    = f'{PREPROC_DIR}/FIACH/rfBrainMask.nii'
brain_out_path   = f'{PREPROC_DIR}/FIACH/Masked_UNI_epispace.nii'

# Mean functional: prefer run-specific, fall back to generic
func_path = f'{PREPROC_DIR}/mc/meanFunctional_{RUN_NAME}.nii.gz'
if not os.path.isfile(func_path):
    fb = f'{PREPROC_DIR}/mc/meanFunctional.nii.gz'
    if os.path.isfile(fb):
        print(f'Using fallback mean functional: {fb}')
        func_path = fb
    else:
        raise FileNotFoundError(
            f'Mean functional not found at:\n  {func_path}\n  {fb}\n'
            f'Check that Step 3 completed successfully.')

print(f'Using mean functional: {func_path}')

# --- Check SynthSeg outputs exist ---
for p in [synthseg_path, brain_mask_path, brain_path_toreg]:
    if not os.path.isfile(p):
        raise FileNotFoundError(
            f'SynthSeg output not found: {p}\n'
            f'Check that Step 5 SynthSeg completed successfully.')

# ============================================================
# STEP 1: Masked_UNI.nii already produced by mri_mask in wrapper
# ============================================================
print(f'Using skull-stripped T1: {brain_path_toreg}')

# ============================================================
# STEP 2: Resample SynthSeg outputs to T1 native space
# ============================================================
print('Resampling SynthSeg outputs to T1 native space...')
t1_nib       = nib.load(t1_path)
seg_nib      = nib.load(synthseg_path)
mask_nib     = nib.load(brain_mask_path)

seg_t1space  = resample_to_img(seg_nib,  t1_nib, interpolation='nearest')
mask_t1space = resample_to_img(mask_nib, t1_nib, interpolation='nearest')

# WM mask: label 2 = Left-WM, 41 = Right-WM
seg_data = seg_t1space.get_fdata()
wm_mask  = ((seg_data == 2) | (seg_data == 41)).astype(np.float32)
nib.save(nib.Nifti1Image(wm_mask, t1_nib.affine, t1_nib.header), wm_mask_path)
print(f'WM mask saved: {wm_mask_path}')

# ============================================================
# STEP 3: Build expanded brain mask (morphological ops)
# ============================================================
print('Building expanded brain mask for EPI registration...')
mask_data = (mask_t1space.get_fdata() > 0).astype(np.float32)
se_close  = np.ones((7, 7, 7), dtype=bool)
se_dilate = np.ones((2, 2, 2), dtype=bool)
closed    = binary_closing(mask_data, structure=se_close)
dilated   = binary_dilation(closed,   structure=se_dilate)
filled    = binary_fill_holes(dilated).astype(np.float32)

img_t1  = ants.image_read(t1_path)
mask_t1 = img_t1.new_image_like(filled)

# ============================================================
# STEP 4: Register T1 to EPI space (ANTs BOLDRigid)
# ============================================================
print('Registering T1 to EPI space (BOLDRigid)...')
meanFunc     = ants.image_read(func_path)
registration = ants.registration(
    fixed=meanFunc, moving=img_t1,
    type_of_transform='BOLDRigid', verbose=True
)

# ============================================================
# STEP 5: Apply transform to mask and save EPI-space outputs
# ============================================================
mask_epi = ants.apply_transforms(
    fixed=meanFunc, moving=mask_t1,
    transformlist=registration['fwdtransforms'],
    interpolator='nearestNeighbor'
)

meanFunc_nib = nib.load(func_path)
mask_final   = (mask_epi.numpy() > 0.5).astype(np.float32)
warped_t1    = registration['warpedmovout'].numpy()
brain_masked = warped_t1 * mask_final

nib.save(nib.Nifti1Image(mask_final,                      meanFunc_nib.affine, meanFunc_nib.header), mask_out_path)
nib.save(nib.Nifti1Image(brain_masked.astype(np.float32), meanFunc_nib.affine, meanFunc_nib.header), brain_out_path)

print('Unique mask values:', np.unique(mask_final))
print('Brain voxels:',       int(mask_final.sum()))
print('Mask saved:',         mask_out_path)
print('Masked brain saved:', brain_out_path)