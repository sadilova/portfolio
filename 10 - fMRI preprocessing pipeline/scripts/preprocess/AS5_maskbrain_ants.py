import ants
import nibabel as nib
import numpy as np
import os
from scipy.ndimage import binary_fill_holes, binary_closing, binary_dilation
from antspynet import brain_extraction
from pathlib import Path

DIR = Path('1_directory.txt').read_text().strip()

SUB = os.environ.get('SUB')
if not SUB:
    raise ValueError("SUB not defined. Please export SUB from the wrapper.")

RUN_LABEL = os.environ.get('RUN_LABEL')
if not RUN_LABEL:
    raise ValueError("RUN_LABEL not defined. Please export RUN_LABEL from the wrapper.")

# --- Paths ---
preproc_dir  = f'{DIR}derivatives/{SUB}/preproc'
fiach_dir    = f'{preproc_dir}/FIACH'
mc_dir       = f'{preproc_dir}/mc'
t1_dir       = f'{preproc_dir}/T1'

t1_path          = f'{fiach_dir}/UNI_T1.nii'
mask_out_path    = f'{fiach_dir}/rfBrainMask.nii'
brain_out_path   = f'{fiach_dir}/Masked_UNI_epispace.nii'
brain_path_toreg = f'{fiach_dir}/Masked_UNI.nii'
t1_path_toreg    = f'{t1_dir}/Masked_UNI.nii'

# Mean functional: prefer run-specific file, fall back to generic
func_path = f'{mc_dir}/meanFunctional_{RUN_LABEL}.nii.gz'
if not os.path.isfile(func_path):
    func_path_fallback = f'{mc_dir}/meanFunctional.nii.gz'
    if os.path.isfile(func_path_fallback):
        print(f'Run-specific mean functional not found, using fallback: {func_path_fallback}')
        func_path = func_path_fallback
    else:
        raise FileNotFoundError(
            f'Mean functional not found at either:\n'
            f'  {func_path}\n'
            f'  {func_path_fallback}\n'
            f'Check that Step 3 completed successfully.'
        )

print(f'Using mean functional: {func_path}')

# --- Load images ---
img      = ants.image_read(t1_path)
meanFunc = ants.image_read(func_path)

# --- Brain extraction ---
mask_prob = brain_extraction(img, modality="t1")
mask_data = mask_prob.numpy()

# Binarise mask
mask_bin = ants.threshold_image(mask_prob, low_thresh=0.5, high_thresh=1.0, inval=1, outval=0)

# ----- Masked T1 in native space — save for coregistration (AS8) -----
brain_extract = img * mask_bin
ants.image_write(brain_extract, brain_path_toreg)
ants.image_write(brain_extract, t1_path_toreg)
print(f'Masked T1 saved: {brain_path_toreg}')

# ----- Build expanded mask for FIACH -----
mask_binary = (mask_data > 0.3).astype(np.float32)
se_close  = np.ones((7, 7, 7), dtype=bool)
se_dilate = np.ones((2, 2, 2), dtype=bool)

closed = binary_closing(mask_binary, structure=se_close)
dilated = binary_dilation(closed, structure=se_dilate)
filled = binary_fill_holes(dilated).astype(np.float32)

mask_t1 = img.new_image_like(filled)

# ----- Register T1 to EPI -----
registration = ants.registration(
    fixed=meanFunc,
    moving=img,
    type_of_transform='BOLDRigid',
    verbose=True
)

# ----- Apply transform to mask -----
mask_epi = ants.apply_transforms(
    fixed=meanFunc,
    moving=mask_t1,
    transformlist=registration['fwdtransforms'],
    interpolator='nearestNeighbor'
)

# ----- Save outputs -----
meanFunc_nib = nib.load(func_path)
mask_final   = (mask_epi.numpy() > 0.5).astype(np.float32)

warped_t1    = registration['warpedmovout'].numpy()
brain_masked = warped_t1 * mask_final

nib.save(
    nib.Nifti1Image(mask_final, meanFunc_nib.affine, meanFunc_nib.header),
    mask_out_path
)
nib.save(
    nib.Nifti1Image(brain_masked.astype(np.float32), meanFunc_nib.affine, meanFunc_nib.header),
    brain_out_path
)

print('Unique mask values:', np.unique(mask_final))
print('Brain voxels:',       int(mask_final.sum()))
print('Mask saved:',         mask_out_path)
print('Masked brain saved:', brain_out_path)