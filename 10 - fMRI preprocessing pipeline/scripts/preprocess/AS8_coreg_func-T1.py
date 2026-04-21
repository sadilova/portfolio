import ants
from pathlib import Path
import os

DIR = Path('1_directory.txt').read_text().strip()

SUB = os.environ.get('SUB')
if not SUB:
    raise ValueError("SUB not defined. Please export SUB from the wrapper.")

RUN_LABEL = os.environ.get('RUN_LABEL')
if not RUN_LABEL:
    raise ValueError("RUN_LABEL not defined. Please export RUN_LABEL from the wrapper.")

REG_FILE = os.environ.get('reg_file')
if not REG_FILE:
    raise ValueError("reg_file not defined. Please export reg_file from the wrapper.")

# --- Paths ---
mc_dir    = f'{DIR}derivatives/{SUB}/preproc/mc'
t1_path   = f'{DIR}derivatives/{SUB}/preproc/T1/Masked_UNI.nii'
func_path = f'{DIR}derivatives/{SUB}/preproc/FIACH/{REG_FILE}.nii'
reg_out   = f'{DIR}derivatives/{SUB}/preproc/reg/reg_{REG_FILE}.nii.gz'

# Mean functional: prefer run-specific, fall back to generic
meanfunc_path = f'{mc_dir}/meanFunctional_{RUN_LABEL}.nii.gz'
if not os.path.isfile(meanfunc_path):
    meanfunc_path_fallback = f'{mc_dir}/meanFunctional.nii.gz'
    if os.path.isfile(meanfunc_path_fallback):
        print(f'Run-specific mean functional not found, using fallback: {meanfunc_path_fallback}')
        meanfunc_path = meanfunc_path_fallback
    else:
        raise FileNotFoundError(
            f'Mean functional not found at either:\n'
            f'  {meanfunc_path}\n'
            f'  {meanfunc_path_fallback}\n'
            f'Check that Step 3 completed successfully.'
        )

print(f'Using mean functional: {meanfunc_path}')

# --- Load ---
img_t1   = ants.image_read(t1_path)
func_4d  = ants.image_read(func_path)
meanfunc = ants.image_read(meanfunc_path)

# --- Register EPI to T1 ---
registration = ants.registration(
    fixed=img_t1,
    moving=meanfunc,
    type_of_transform='BOLDRigid',
    verbose=True
)

print('Applying transformations (volume by volume to reduce memory)...')

# Split into 3D volumes, transform each, then reassemble
# This avoids loading the entire 4D array into ANTs memory at once
n_vols = func_4d.shape[-1]
reg_vols = []

for i in range(n_vols):
    if i % 20 == 0:
        print(f'  Transforming volume {i+1}/{n_vols}...')
    vol_3d = ants.slice_image(func_4d, axis=3, idx=i)
    reg_vol = ants.apply_transforms(
        fixed=img_t1,
        moving=vol_3d,
        transformlist=registration['fwdtransforms']
    )
    reg_vols.append(reg_vol)

reg_func_4d = ants.list_to_ndimage(func_4d, reg_vols)

# --- Save ---
print('Saving registered image...')
ants.image_write(reg_func_4d, reg_out)
print(f'Registered 4D EPI saved: {reg_out}')