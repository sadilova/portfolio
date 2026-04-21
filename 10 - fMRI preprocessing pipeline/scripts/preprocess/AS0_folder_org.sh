dir=$(cat 1_directory.txt)
mapfile -t subs < 1_subjects.txt

for sub in "${subs[@]}"; do
    mkdir -p "${dir}derivatives/${sub}/preproc/mc"
    mkdir -p "${dir}derivatives/${sub}/preproc/slicecor"
    mkdir -p "${dir}derivatives/${sub}/preproc/T1"
    mkdir -p "${dir}derivatives/${sub}/preproc/NORDIC"
    mkdir -p "${dir}derivatives/${sub}/preproc/FIACH"
    mkdir -p "${dir}derivatives/${sub}/preproc/smooth"
    mkdir -p "${dir}derivatives/${sub}/preproc/reg"
    mkdir -p "${dir}derivatives/${sub}/preproc/tsnr"
    mkdir -p "${dir}derivatives/${sub}/preproc/checkpoints"
    mkdir -p "${dir}derivatives/${sub}/stats"
    echo "  Created folders for ${sub}"
done
