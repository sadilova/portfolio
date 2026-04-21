import ants
import nibabel as nib
import numpy as np
import os
from scipy.ndimage import binary_fill_holes, binary_closing, binary_dilation
from antspynet import brain_extraction
from pathlib import Path

DIR       = Path('1_directory.txt').read_text().strip()
SUB       = os.environ.get('SUB')
RUN_NAME  = os.environ.get('RUN_NAME')
PREPROC_DIR = os.environ.get('PREPROC_DIR')
T1_DIR    = os.environ.get('T1_DIR')

if not SUB:        raise ValueError("SUB not defined.")
if not RUN_NAME:   raise ValueError("RUN_NAME not defined.")
if not PREPROC_DIR: raise ValueError("PREPROC_DIR not defined.")
if not T1_DIR:     raise ValueError("T1_DIR not defined.")

# --- Paths ---
# T1 lives in shared T1_DIR; EPI-space outputs go to cap-specific PREPROC_DIR/FIACH/
t1_path          = f'{T1_DIR}/UNI_T1.nii'
mask_out_path    = f'{PREPROC_DIR}/FIACH/rfBrainMask.nii'
brain_out_path   = f'{PREPROC_DIR}/FIACH/Masked_UNI_epispace.nii'
brain_path_toreg = f'{T1_DIR}/Masked_UNI.nii'

# Mean functional: prefer run-specific, fall back to generic
func_path = f'{PREPROC_DIR}/mc/meanFunctional_{RUN_NAME}.nii.gz'
if not os.path.isfile(func_path):
    func_path_fb = f'{PREPROC_DIR}/mc/meanFunctional.nii.gz'
    if os.path.isfile(func_path_fb):
        print(f'Using fallback mean functional: {func_path_fb}')
        func_path = func_path_fb
    else:
        raise FileNotFoundError(
            f'Mean functional not found at:\n  {func_path}\n  {func_path_fb}')

print(f'Using mean functional: {func_path}')

# --- Load ---
img      = ants.image_read(t1_path)
meanFunc = ants.image_read(func_path)

# --- Brain extraction on T1 ---
# Only rerun if Masked_UNI.nii doesn't exist yet (T1 is shared across caps)
if not os.path.isfile(brain_path_toreg):
    print('Running brain extraction on T1...')
    mask_prob = brain_extraction(img, modality='t1')
    mask_bin  = ants.threshold_image(mask_prob, low_thresh=0.5, high_thresh=1.0, inval=1, outval=0)
    brain_extract = img * mask_bin
    ants.image_write(brain_extract, brain_path_toreg)
    print(f'Masked T1 saved: {brain_path_toreg}')
else:
    print(f'Masked T1 already exists, skipping extraction: {brain_path_toreg}')
    mask_prob = brain_extraction(img, modality='t1')
    mask_bin  = ants.threshold_image(mask_prob, low_thresh=0.5, high_thresh=1.0, inval=1, outval=0)

# --- Build expanded EPI mask ---
mask_data   = mask_prob.numpy()
mask_binary = (mask_data > 0.3).astype(np.float32)
se_close    = np.ones((7, 7, 7), dtype=bool)
se_dilate   = np.ones((2, 2, 2), dtype=bool)
closed  = binary_closing(mask_binary, structure=se_close)
dilated = binary_dilation(closed,     structure=se_dilate)
filled  = binary_fill_holes(dilated).astype(np.float32)
mask_t1 = img.new_image_like(filled)

# --- Register T1 to EPI ---
registration = ants.registration(
    fixed=meanFunc, moving=img,
    type_of_transform='BOLDRigid', verbose=True
)

# --- Apply transform to mask ---
mask_epi = ants.apply_transforms(
    fixed=meanFunc, moving=mask_t1,
    transformlist=registration['fwdtransforms'],
    interpolator='nearestNeighbor'
)

# --- Save EPI-space outputs ---
meanFunc_nib = nib.load(func_path)
mask_final   = (mask_epi.numpy() > 0.5).astype(np.float32)
warped_t1    = registration['warpedmovout'].numpy()
brain_masked = warped_t1 * mask_final

nib.save(nib.Nifti1Image(mask_final, meanFunc_nib.affine, meanFunc_nib.header), mask_out_path)
nib.save(nib.Nifti1Image(brain_masked.astype(np.float32), meanFunc_nib.affine, meanFunc_nib.header), brain_out_path)

print('Unique mask values:', np.unique(mask_final))
print('Brain voxels:',       int(mask_final.sum()))
print('Mask saved:',         mask_out_path)
print('Masked brain saved:', brain_out_path)