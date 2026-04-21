#!/bin/bash
# ============================================================
# AS0_folder_org.sh
# Creates subject-level shared folders only.
# Cap-specific preproc subfolders are created by the wrapper
# on the fly when each run is processed.
# ============================================================
dir=$(cat 1_directory.txt)
mapfile -t subs < 1_subjects.txt

for sub in "${subs[@]}"; do
    # Shared subject-level folders
    mkdir -p "${dir}derivatives/${sub}/preproc/T1"
    mkdir -p "${dir}derivatives/${sub}/preproc/checkpoints"
    mkdir -p "${dir}derivatives/${sub}/stats"
    echo "  Created shared folders for ${sub}"
done