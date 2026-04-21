import ants
import os
from pathlib import Path

DIR         = Path('1_directory.txt').read_text().strip()
SUB         = os.environ.get('SUB')
RUN_NAME    = os.environ.get('RUN_NAME')
PREPROC_DIR = os.environ.get('PREPROC_DIR')
T1_DIR      = os.environ.get('T1_DIR')
REG_FILE    = os.environ.get('reg_file')

if not SUB:         raise ValueError("SUB not defined.")
if not RUN_NAME:    raise ValueError("RUN_NAME not defined.")
if not PREPROC_DIR: raise ValueError("PREPROC_DIR not defined.")
if not T1_DIR:      raise ValueError("T1_DIR not defined.")
if not REG_FILE:    raise ValueError("reg_file not defined.")

# --- Paths ---
t1_path   = f'{T1_DIR}/Masked_UNI.nii'
func_path = f'{PREPROC_DIR}/FIACH/{REG_FILE}.nii'
reg_out   = f'{PREPROC_DIR}/reg/reg_{REG_FILE}.nii.gz'

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

# --- Load ---
img_t1   = ants.image_read(t1_path)
func_4d  = ants.image_read(func_path)
meanfunc = ants.image_read(meanfunc_path)

# --- Register EPI to T1 ---
registration = ants.registration(
    fixed=img_t1, moving=meanfunc,
    type_of_transform='BOLDRigid', verbose=True
)

print('Applying transformations (volume by volume)...')
n_vols = func_4d.shape[-1]
reg_vols = []
for i in range(n_vols):
    if i % 20 == 0: print(f'  Volume {i+1}/{n_vols}...')
    vol_3d  = ants.slice_image(func_4d, axis=3, idx=i)
    reg_vol = ants.apply_transforms(
        fixed=img_t1, moving=vol_3d,
        transformlist=registration['fwdtransforms']
    )
    reg_vols.append(reg_vol)

reg_func_4d = ants.list_to_ndimage(func_4d, reg_vols)

print('Saving registered image...')
ants.image_write(reg_func_4d, reg_out)
print(f'Registered 4D EPI saved: {reg_out}')