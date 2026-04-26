# ------------------------------
# To run interactively:
#   conda activate neuro
#   cd /data/Annie/PROJECTS/scripts
#   python preproc_qc.py
#
# Called automatically by wrapper:
#   python preproc_qc.py <SUB> <RUN_LABEL>
# ------------------------------

import sys
import base64
from pathlib import Path
import numpy as np
import pandas as pd
from dotenv import dotenv_values
from nilearn import plotting, image

# ─── CONFIG ───────────────────────────────────────────────────────────────────
DIR = (Path(__file__).parent / '1_directory.txt').read_text().strip()

if len(sys.argv) > 2:
    # Called non-interactively by wrapper — no listing, no prompt
    SUB, RUN_LABEL = sys.argv[1], sys.argv[2]
    selected = [(SUB, RUN_LABEL, None)]
else:
    # Interactive mode — discover and prompt
    env_files = sorted(Path(DIR + 'derivatives').glob('sub-*/stats/pipeline_vars_*.env'))

    if not env_files:
        print('No pipeline_vars_*.env files found.')
        sys.exit(1)

    combos = []
    for f in env_files:
        sub       = f.parts[-3]
        run_label = f.stem.replace('pipeline_vars_', '')
        combos.append((sub, run_label, f))

    print('Available runs:')
    for i, (sub, run_label, _) in enumerate(combos):
        print(f'  [{i}] {sub}  {run_label}')

    choice = input('\nEnter index (or press Enter to run ALL): ').strip()
    selected = combos if choice == '' else [combos[int(choice)]]

# ─── HTML HELPERS ─────────────────────────────────────────────────────────────
def h1(sections, text):
    sections.append(f'<h1>{text}</h1>')

def h2(sections, text):
    sections.append(f'<h2>{text}</h2>')

def h3(sections, text):
    sections.append(f'<h3>{text}</h3>')

def skip(sections, text):
    sections.append(f'<p style="color:#c0392b;font-family:monospace">[SKIP] {text}</p>')

def preformat(sections, text):
    escaped = text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    sections.append(f'<pre style="background:#f4f4f4;padding:10px;border-radius:4px">{escaped}</pre>')

def add_view(sections, view, title=''):
    if title:
        h3(sections, title)
    sections.append(view._repr_html_())

def add_png(sections, path, title='', width=700):
    if title:
        h3(sections, title)
    data = base64.b64encode(Path(path).read_bytes()).decode()
    sections.append(f'<img src="data:image/png;base64,{data}" width="{width}" style="display:block;margin:10px 0">')

def add_dataframe(sections, df, title=''):
    if title:
        h3(sections, title)
    sections.append(df.to_html(classes='qc-table', border=0))

# ─── PER-RUN REPORT FUNCTION ──────────────────────────────────────────────────
def run_qc(SUB, RUN_LABEL):
    print(f'\nRunning QC: {SUB} / {RUN_LABEL}')
    sections = []

    config = dotenv_values(f'{DIR}derivatives/{SUB}/stats/pipeline_vars_{RUN_LABEL}.env')

    PREPROC_DIR = config.get('PREPROC_DIR') or None
    T1_DIR      = config.get('T1_DIR') or None

    CAP_NAME = config.get('CAP_NAME') or ''
    RUN_NAME = config.get('RUN_NAME') or (
        RUN_LABEL.split('_', 1)[-1] if '_' in RUN_LABEL else RUN_LABEL
    )

    if not PREPROC_DIR:
        PREPROC_DIR = f'{DIR}derivatives/{SUB}/preproc/{CAP_NAME}' if CAP_NAME \
                      else f'{DIR}derivatives/{SUB}/preproc'
        print(f'  WARNING: PREPROC_DIR not in env, derived as: {PREPROC_DIR}')
    if not T1_DIR:
        T1_DIR = f'{DIR}derivatives/{SUB}/preproc/T1'
        print(f'  WARNING: T1_DIR not in env, derived as: {T1_DIR}')

    mc_file     = config.get('mc_file')
    sc_file     = config.get('sc_file')
    fiach_file  = config.get('fiach_file')
    reg_file    = config.get('reg_file')
    smooth_file = config.get('smooth_file')

    anat     = f'{T1_DIR}/Masked_UNI.nii'
    nordic   = f'{PREPROC_DIR}/NORDIC/{mc_file}.nii'
    mc       = f'{PREPROC_DIR}/mc/{mc_file}_mcf.nii.gz'
    fiach    = f'{PREPROC_DIR}/FIACH/{reg_file}.nii'
    reg      = f'{PREPROC_DIR}/reg/reg_{reg_file}.nii.gz'
    norm     = f'{PREPROC_DIR}/reg/norm_{reg_file}.nii'
    smooth   = f'{PREPROC_DIR}/smooth/{smooth_file}_smooth.nii.gz'
    meanfunc = f'{PREPROC_DIR}/mc/meanFunctional_{RUN_NAME}.nii.gz'
    mask_epi = f'{PREPROC_DIR}/FIACH/rfBrainMask_{RUN_NAME}.nii'

    # ── Header + path check ───────────────────────────────────────────────────
    h1(sections, f'Preprocessing QC — {SUB} / {RUN_LABEL}')

    lines = [f'RUN_NAME = {RUN_NAME}', '']
    for label, path in [('anat',     anat),
                        ('nordic',   nordic),
                        ('mc',       mc),
                        ('meanfunc', meanfunc),
                        ('fiach',    fiach),
                        ('reg',      reg),
                        ('norm',     norm),
                        ('smooth',   smooth),
                        ('mask_epi', mask_epi)]:
        mark = '✓' if Path(path).exists() else '✗ MISSING'
        lines.append(f'  [{mark}] {label}: {path}')
    preformat(sections, '\n'.join(lines))

    # ── Realignment ───────────────────────────────────────────────────────────
    h2(sections, 'Realignment and unwarping')

    for label, fname in [('Translation',  f'{mc_file}_mcf_trans.png'),
                         ('Rotation',     f'{mc_file}_mcf_rot.png'),
                         ('Displacement', f'{mc_file}_mcf_disp.png')]:
        p = f'{PREPROC_DIR}/mc/{fname}'
        if Path(p).exists():
            add_png(sections, p, title=label, width=800)
        else:
            skip(sections, f'{label} plot not found: {p}')

    meanNORfunc    = None
    meanNORmcufunc = None

    if Path(nordic).exists():
        meanNORfunc = image.mean_img(nordic)
    else:
        skip(sections, f'NORDIC not found: {nordic}')

    mc_sc = f'{PREPROC_DIR}/mc/{sc_file}.nii.gz'
    if Path(mc_sc).exists():
        meanNORmcufunc = image.mean_img(mc_sc)
    else:
        skip(sections, f'mc/unwarp not found: {mc_sc}')

    if meanNORfunc and meanNORmcufunc:
        add_view(sections,
                 plotting.view_img(meanNORfunc, bg_img=False, black_bg=True,
                                   cmap='gray', symmetric_cmap=False,
                                   title='NORDIC'),
                 title='NORDIC')
        add_view(sections,
                 plotting.view_img(meanNORmcufunc, bg_img=False, black_bg=True,
                                   cmap='gray', symmetric_cmap=False,
                                   title='mc/unwarp'),
                 title='mc/unwarp')
        add_view(sections,
                 plotting.view_img(meanNORfunc, bg_img=meanNORmcufunc,
                                   title='NORDIC vs mc/unwarp',
                                   cmap='hot', opacity=0.4, symmetric_cmap=False),
                 title='NORDIC vs mc/unwarp')

    h2(sections, 'EPI overlaid on T1')
    if meanNORfunc and Path(anat).exists():
        add_view(sections,
                 plotting.view_img(meanNORfunc, bg_img=anat, black_bg=True,
                                   title='EPI over T1', opacity=0.2, symmetric_cmap=False),
                 title='EPI over T1')
    else:
        skip(sections, 'meanNORfunc or anat not available')

    if meanNORmcufunc and Path(anat).exists():
        add_view(sections,
                 plotting.view_img(meanNORmcufunc, bg_img=anat, black_bg=True,
                                   title='mc/unwarp over T1', opacity=0.2, symmetric_cmap=False),
                 title='mc/unwarp over T1')
    else:
        skip(sections, 'meanNORmcufunc or anat not available')

    # ── Brain masking ─────────────────────────────────────────────────────────
    h2(sections, 'Brain masking')

    UNI = f'{T1_DIR}/UNI_T1.nii'
    if Path(anat).exists() and Path(UNI).exists():
        add_view(sections,
                 plotting.view_img(anat, bg_img=UNI, black_bg=True,
                                   title='T1 extraction',
                                   opacity=0.3, symmetric_cmap=False),
                 title='T1 extraction (Masked_UNI over UNI_T1)')
    else:
        skip(sections, 'T1 or UNI not found')

    if Path(mask_epi).exists() and Path(meanfunc).exists():
        add_view(sections,
                 plotting.view_img(mask_epi, bg_img=meanfunc, black_bg=True,
                                   title='rfBrainMask over meanFunctional',
                                   cmap='jet', opacity=0.3, symmetric_cmap=False),
                 title='rfBrainMask over meanFunctional')
    else:
        skip(sections, 'mask_epi or meanfunc not found')

    # ── FIACH ─────────────────────────────────────────────────────────────────
    h2(sections, 'FIACH outputs')

    for img in ['FIACH_GMM_fit.png',
                'FIACH_TSNR_midslice.png',
                'FIACH_NoisyMask_midslice.png',
                'FIACH_QC_corrections_per_frame.png',
                'FIACH_QC_worstvoxel_1.png',
                'FIACH_QC_worstvoxel_2.png',
                'FIACH_QC_worstvoxel_3.png']:
        p = f'{PREPROC_DIR}/FIACH/{img}'
        if Path(p).exists():
            add_png(sections, p, title=img.replace('.png', '').replace('_', ' '), width=500)
        else:
            skip(sections, img)

    h3(sections, 'FIACH log')
    log_path = f'{PREPROC_DIR}/FIACH/fiach_log_{RUN_NAME}.txt'
    if Path(log_path).exists():
        preformat(sections, Path(log_path).read_text())
    else:
        skip(sections, f'FIACH log not found: {log_path}')

    h3(sections, 'Confound file (should have 12 columns)')
    conf_path = f'{PREPROC_DIR}/FIACH/multi_reg_FIACH_6PCs_{SUB}_{RUN_LABEL}.txt'
    if Path(conf_path).exists():
        df_conf = pd.DataFrame(np.loadtxt(conf_path))
        add_dataframe(sections, df_conf.head(15))
        h3(sections, f'({len(df_conf)} rows total, showing first 15)')
    else:
        skip(sections, f'Confound file not found: {conf_path}')

    # ── Co-registration ───────────────────────────────────────────────────────
    h2(sections, 'Co-registration (EPI to T1)')

    meancoregepi = None
    if Path(reg).exists() and Path(anat).exists():
        meancoregepi = image.mean_img(reg)
        add_view(sections,
                 plotting.view_img(meancoregepi, bg_img=anat, black_bg=True,
                                   title='EPI registered to T1',
                                   opacity=0.3, symmetric_cmap=False),
                 title='EPI registered to T1')
    else:
        skip(sections, 'reg or anat not found')

    # ── Normalisation ─────────────────────────────────────────────────────────
    h2(sections, 'Normalisation')

    if Path(norm).exists():
        meanmnifunc = image.mean_img(norm)
        add_view(sections,
                 plotting.view_img(meanmnifunc, bg_img=anat, black_bg=True,
                                   title='mniFunc over native',
                                   opacity=0.3, symmetric_cmap=False),
                 title='mniFunc over native T1')
        add_view(sections,
                 plotting.view_img(meanmnifunc, black_bg=True,
                                   title='mniFunc over MNI',
                                   opacity=0.3, symmetric_cmap=False),
                 title='mniFunc over MNI template')
    else:
        skip(sections, f'norm not found: {norm}')

    # ── Smoothing ─────────────────────────────────────────────────────────────
    h2(sections, 'Smoothing')

    if Path(smooth).exists():
        meansmooth         = image.mean_img(smooth, copy_header=True)
        meansmooth_clipped = image.math_img("np.clip(img, 0, None)", img=meansmooth)

        if meancoregepi:
            meancoregepi_clipped = image.math_img("np.clip(img, 0, None)", img=meancoregepi)
            add_view(sections,
                     plotting.view_img(meancoregepi_clipped, bg_img=False, black_bg=True,
                                       cmap='Greys_r', symmetric_cmap=False, vmin=0,
                                       title='EPI before smoothing'),
                     title='EPI before smoothing')

        add_view(sections,
                 plotting.view_img(meansmooth_clipped, bg_img=False, black_bg=True,
                                   cmap='Greys_r', symmetric_cmap=False, vmin=0,
                                   title='Smoothed EPI'),
                 title='Smoothed EPI')
    else:
        skip(sections, f'smooth not found: {smooth}')

    # ── tSNR ──────────────────────────────────────────────────────────────────
    h2(sections, 'tSNR maps')

    tsnr_dir = f'{PREPROC_DIR}/tsnr'
    vmin, vmax = 0, 250

    tsnr_files = {
        'NORDIC (pre-mc)'       : f'{tsnr_dir}/NORDIC_Run_BOLD_{SUB}_{RUN_NAME}_tsnr.nii.gz',
        'realigned/unwarped'    : f'{tsnr_dir}/{mc_file}_mcf_tsnr.nii.gz',
        'preregistered (FIACH)' : f'{tsnr_dir}/{reg_file}_tsnr.nii.gz',
        'registered (T1)'       : f'{tsnr_dir}/reg_{reg_file}_tsnr.nii.gz',
        'normalised (MNI)'      : f'{tsnr_dir}/norm_{reg_file}_tsnr.nii.gz',
        'smoothed'              : f'{tsnr_dir}/{smooth_file}_smooth_tsnr.nii.gz',
    }

    for title, path in tsnr_files.items():
        if not Path(path).exists():
            skip(sections, f'{title}: {path}')
            continue
        clipped = image.math_img("np.clip(img, 0, None)", img=path)
        add_view(sections,
                 plotting.view_img(clipped, bg_img=False, black_bg=True, cmap='jet',
                                   symmetric_cmap=False, vmin=vmin, vmax=vmax,
                                   colorbar=True, title=title),
                 title=title)

    # ── Write HTML ────────────────────────────────────────────────────────────
    output_dir  = Path(f'{DIR}derivatives/{SUB}/')
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f'{SUB}_{RUN_LABEL}_qc.html'

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>QC — {SUB} {RUN_LABEL}</title>
  <style>
    body       {{ font-family: sans-serif; max-width: 1100px; margin: 40px auto; padding: 0 20px; background: #fff; }}
    h1         {{ border-bottom: 2px solid #333; padding-bottom: 8px; }}
    h2         {{ border-bottom: 1px solid #ccc; margin-top: 40px; color: #2c3e50; }}
    h3         {{ color: #555; margin-top: 24px; }}
    .qc-table  {{ border-collapse: collapse; font-size: 12px; }}
    .qc-table td, .qc-table th {{ border: 1px solid #ddd; padding: 4px 8px; }}
    .qc-table th {{ background: #f0f0f0; }}
  </style>
</head>
<body>
{''.join(sections)}
</body>
</html>"""

    output_path.write_text(html, encoding='utf-8')
    print(f'  Saved: {output_path}')


# ─── RUN ──────────────────────────────────────────────────────────────────────
for SUB, RUN_LABEL, _ in selected:
    run_qc(SUB, RUN_LABEL)

print('\nDone.')