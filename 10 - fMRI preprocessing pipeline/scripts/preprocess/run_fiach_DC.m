function run_fiach(rf, rfMean,rfBrainMask, cfg)
    fprintf('Running FIACH preprocessing ...\n');

    % Load data
    V       = spm_vol(rf);
    vol     = spm_read_vols(V);
    mean_V  = spm_vol(rfMean);
    maskV  = spm_vol(rfBrainMask);
    mask     = spm_read_vols(maskV);
    % Mask
    if nargin < 3 
        maskPath = spm_select('FPList', cfg.dirStruct, ['^rfBrainMask_' cfg.sName '\.nii$']);
        Vmask = spm_vol(maskPath);
        mask  = logical(spm_read_vols(Vmask));
    
    end

    if nargin < 4 
        cfg.TR       = 2.6;
        cfg.TE       = 0.024;
        cfg.B0       = 7;
        cfg.nslices  = 111;
        %  cfg.TA       = TA_s;
        cfg.sliceord = 1:111;
        % --- AS added 3.3.26 ---
        cfg.do_hpf        = false;
        cfg.do_regression = false;
        cfg.debug         = false;

    end
    
    % --- DEFINE OUTPUT PATH & RUN NAME ---
    pth = pwd;
    [~, runName, ~] = fileparts(rf);
        
    % --- High-pass filter ---
    % --- AS IF statement added 3.3.26 ---
    if cfg.do_hpf
        vol = fiach_highpass_filter(vol, cfg.TR);
    end

    % --- TSNR ---
    [TSNR_vol, TSNR_vox] = fiach_tsnr(vol, mask);
    TSNR_vol(~isfinite(TSNR_vol)) = 0;

    % Save TSNR (per run)
    tsnrFile = fullfile(['tsnr_', rf]);
    mean_V.fname = tsnrFile;
    spm_write_vol(mean_V, TSNR_vol);

    % --- Fit GMM & noisy voxels ---
    fprintf(' - Fitting GMM...\n');
    [gmmfit, ~, ~, ~, ~, ~] = TSNR_gmm(TSNR_vol(find(TSNR_vol)));
    Mask_noisy = fiach_segment_noisy(TSNR_vox, mask, gmmfit);

    % Save noisy mask (per run)
    VmaskOut = mean_V;
    VmaskOut.fname = fullfile(['Mask_noisy_',rf])
    spm_write_vol(VmaskOut, double(Mask_noisy));

    % (optional) QC check
    fiach_check_tsnr(TSNR_vol, Mask_noisy);

    % --- PCA ---
    [pca_coeff, pca_score, pca_latent, pca_tsquared, explained] = NoisyPCA(vol, Mask_noisy);
    k = min(6, numel(explained));
    fprintf('First %d PCA components explain %.2f%% of variance in noisy voxels.\n', ...
        k, sum(explained(1:k)));

    if ~isempty(pca_score)
    
        % --- DEFINE OUTPUT PATH & RUN NAME ---
        pth = pwd;
        [~, runName, ~] = fileparts(rf);
        % e.g. rf = rNORDIC_S01_Run_2_trimmed.nii
        % runName = 'rNORDIC_S01_Run_2_trimmed'
        
        pcs_tsv = fullfile(pth, sprintf('noisyPCs_%s.tsv', runName));
    
        try
            writematrix(pca_score(:,1:k), pcs_tsv, 'Delimiter', '\t');
        catch
            fid = fopen(pcs_tsv, 'w');
            for i = 1:size(pca_score,1)
                fprintf(fid, repmat('%g\t', 1, k), pca_score(i,1:k));
                fprintf(fid, '\n');
            end
            fclose(fid);
        end
    end
    
            
    % --- Temporal noise regression ---
    %example noise regression step - put into function later
    % AS IF statement added 3.3.26
    if cfg.do_regression && ~isempty(pca_score)
        volSize = size(vol);
        frameSize = volSize(1:3);
        nFrames = volSize(4); 
        vol_tmp=reshape(vol,[frameSize(1)*frameSize(2)*frameSize(3) nFrames]);
        X=pca_score;
        Xinv=pinv(X);
        Ynew=zeros([size(vol_tmp)]);
        for b = 1:frameSize(1)*frameSize(2)*frameSize(3)
            if mask(b)==1
                Ynew(b,:) = vol_tmp(b,:) - (X * (Xinv * vol_tmp(b,:)'))';
            end
        end
        vol_new=reshape(Ynew,[frameSize nFrames]);
        % --- AS added 3.3.26 ---
        outPath1 = fullfile(pth, sprintf('regress_%s.nii', runName));
        save_4d_nifti(vol_new, V(1), outPath1);
        vol = vol_new;  % pass regressed vol forward to spike interpolation
    end
        
    % --- Temporal outlier correction ---
    Bad_data = LargeTempChanges(vol, mask, cfg.TE, 2.0, 1.96);
    [vol_clean, num_changed] = InterpLargeChanges(vol, Bad_data, true, 2);
    fprintf('Interpolated %d bad data points.\n', num_changed);

    % QC option
    if cfg.debug
        QC_LargeTempChanges(vol, vol_clean, Bad_data);
    end

    % --- Save cleaned file per run ---
    outPath = fullfile(pth, sprintf('rclean_%s.nii', runName));
    save_4d_nifti(vol_clean, V(1), outPath);
end



% ---------------------------------------
% FIACH FUNCTIONS
% ---------------------------------------

function vol = fiach_highpass_filter(vol, TR)
    fprintf(' - Applying high-pass filter...\n');
    K_input = struct('RT', TR, 'HParam', 128, 'row', ones(1, size(vol,4)));
    vol = spm_filter(K_input, vol);
end

function [TSNR_vol, TSNR_vox] = fiach_tsnr(vol, mask)

    % TSNR finds the robust temporal signal to noise ratio 
    % (median / mean absolute deviation) for voxels in mask of volume vol
    
    fprintf("\nFIACH: Finding robust TSNR on volume...\n")
    
    % get vol size
    volSize = size(vol);
    frameSize = volSize(1:3);
    nFrames = volSize(4);   % size in temporal dim
    
    % reshape arrays to access timeseries of each voxel in mask
%    tmp_mask = reshape(mask, [], 1);    %(64^3) by 1
%    tmp_vol = reshape(vol, [], nFrames);%(64^3) by nFrames
    
    %non zero mask elements
    ind=find(mask);
    
    % find medians and mean absolute deviations
    meds = median(vol,4);
    mads = mad(vol,1,4);

    % find TSNR
    TSNR_vol = (meds./mads).*mask; % full vol size
    %TSNR_vol = reshape(TSNR_vol, frameSize);    % reshape back to 3D
    
    TSNR_vox = TSNR_vol(ind); % TSNR of brain region only - 1D list
    
    fprintf("FIACH: TSNR found\n")
end

function [gmm, g1, g2, x, bin_centers, TSNR_98] = TSNR_gmm(TSNR_vox)
    % Fits a 2-component GMM to voxel tSNR (trimming to 98th percentile) and
    % returns the fitted model and two Gaussian curves sampled over the histogram domain.
    
    fprintf("\nFIACH: Fitting gaussian mixture to TSNR...\n");
    
    % 1) Trim to 98th percentile
    TSNR_vox = TSNR_vox(:);                % ensure column
    TSNR_sorted = sort(double(TSNR_vox));  % double, column
    len = numel(TSNR_sorted);
    idx98 = max(1, round(0.98 * len));
    TSNR_98 = TSNR_sorted(1:idx98);
    
    % 2) Define histogram from the actual data range
    nbins = 200;                                % 100–300 is usually cleaner than 1000
    lo = min(TSNR_98);
    hi = max(TSNR_98);
    if ~isfinite(lo) || ~isfinite(hi) || lo == hi
        error('TSNR_gmm:BadRange','tSNR data range is degenerate.');
    end
    edges = linspace(lo, hi, nbins+1);
    bin_centers = (edges(1:end-1) + edges(2:end))/2;
    counts = histcounts(TSNR_98, edges);
    bin_width = edges(2) - edges(1); 
    
    % 3) Build priors from cumulative lower/upper windows
    num_priors = 19;
    l_means = nan(1,num_priors);
    u_means = nan(1,num_priors);
    l_vars  = nan(1,num_priors);
    u_vars  = nan(1,num_priors);
    
    for i = 1:num_priors
        cut = max(1, round(0.05 * i * nbins)); % 5%, 10%, ..., 95%
        lower_w = counts(1:cut);
        upper_w = counts(cut+1:end);
    
        % guard zeros
        swl = sum(lower_w);
        swu = sum(upper_w);
        if swl > 1
            lc = bin_centers(1:cut);
            lm = (lower_w * lc') / swl;
            lv = (lower_w * ((lc - lm).^2)') / swl;
            l_means(i) = lm;
            l_vars(i)  = max(lv, eps);
        end
        if swu > 1
            uc = bin_centers(cut+1:end);
            um = (upper_w * uc') / swu;
            uv = (upper_w * ((uc - um).^2)') / swu;
            u_means(i) = um;
            u_vars(i)  = max(uv, eps);
        end
    end
    
    % 4) Fit GMMs with those priors; keep best
    best_log = inf;
    gmm = [];
    for i = 4:num_priors
        if any(isnan([l_means(i), u_means(i), l_vars(i), u_vars(i)])), continue; end
        mu0 = sort([l_means(i); u_means(i)]);
        s0  = sort([l_vars(i),  u_vars(i)]);
        S   = struct('mu', mu0, 'Sigma', reshape(s0, [1 1 2]));
        try
            gfit = fitgmdist(TSNR_98, 2, 'Start', S, ...
                'Options', statset('MaxIter',500), 'CovarianceType','diagonal');
        catch
            continue
        end
        if gfit.NegativeLogLikelihood < best_log
            best_log = gfit.NegativeLogLikelihood;
            gmm = gfit;
        end
    end
    if isempty(gmm)
        error('TSNR_gmm:NoBestFit', 'No valid GMM fit found. Check initialisations/data.');
    end
    
    % 5) Enforce component order
    [mu_sorted, order] = sort(gmm.mu(:));
    sigma_sorted = sqrt(gmm.Sigma(:,:,order));
    w = gmm.ComponentProportion(order);
    
    % 6) Build Gaussian curves
    x = bin_centers(:);
    gaus = @(x,mu,std,amp,offset) amp .* exp(-0.5*((x-mu)./std).^2) + offset;
    
    total_counts = sum(counts);
    norm_amp = @(std, wgt) (wgt * total_counts * bin_width) / (std * sqrt(2*pi));
    
    g1 = gaus(x, mu_sorted(1), sigma_sorted(1), norm_amp(sigma_sorted(1), w(1)), 0);
    g2 = gaus(x, mu_sorted(2), sigma_sorted(2), norm_amp(sigma_sorted(2), w(2)), 0);
    
    fprintf("FIACH: Gaussian mixture fitted\n");
    
    % 7) PLOT results
    figure;
    set(gcf, 'Visible', 'off');    % ADD - don't display, just save
    bar(bin_centers, counts, 1.0, 'FaceAlpha',0.3,'EdgeColor','none'); hold on;
    plot(x, g1, 'r-', 'LineWidth',2);
    plot(x, g2, 'b-', 'LineWidth',2);
    plot(x, g1+g2, 'k--', 'LineWidth',2);
    xlabel('tSNR'); 
    ylabel('Voxel count');
    legend({'Histogram','Gaussian 1','Gaussian 2','Mixture'}, 'Location','best');
    title('GMM fit to tSNR distribution');
    grid on;
    saveas(gcf, fullfile(pwd, 'FIACH_GMM_fit.png'));
    close(gcf);                    % ADD - clean up after saving
    
    end

function mask = ExtractBrain(segmentedData, probThresh, nDilates, nErodes)
    %ExtractBrain
    %   Returns a mask of the grey matter of the brain from a 3D volume and its
    %   segmented data
    
    fprintf("\nFIACH: Extracting brain mask from segmented data...\n")
    
    V_c1 =spm_vol(segmentedData{1});
    vol_c1 = spm_read_vols(V_c1);
    
    % want a binarised mask of these tissues
    mask = zeros(size(vol_c1));
    
    num_segmented_sets = size(segmentedData);
    num_segmented_sets = num_segmented_sets(2);
    
    % find voxels that belong to segmented data
    for i = 1:num_segmented_sets
        % tissue probability map vols from segmented mean image
        V_c =spm_vol(segmentedData{i});
        vol_c = spm_read_vols(V_c);
    
        tmp = vol_c > probThresh;
        
        mask(tmp) = 1;
    end
    
    % perform dilate and erode on mask
    if nDilates ~= 0
        for i = 1:nDilates
            mask = spm_dilate(mask);
        end
    end
    
    if nErodes ~= 0
        for i = 1:nErodes
            mask = spm_erode(mask);
        end
    end
    
    mask = logical(mask);
    
    fprintf("\nFIACH: Brain mask created\n")
    end

function Mask_noisy= fiach_segment_noisy(TSNR_vox, mask, gmmfit,thr)
% Segment noisy voxels using a 2-component GMM by posterior probability.
% Marks voxels as noisy when P(noise | tSNR) > 0.5 (tunable) use 4th argument thr to alter.

    fprintf("\nFIACH: Segmenting noisy voxels from TSNR...\n");
  % Threshold (Bayes default = 0.5; increase to be more conservative)
    if nargin<4
        thr = 0.5;
    end
    % Shapes
    TSNR_vox = double(TSNR_vox(:));
    TSNR_vox(~isfinite(TSNR_vox)) = 0; % brain voxels only (nnz(mask)×1)
    tmp_mask = mask(:);               % full-volume logical (numel(mask)×1)

    % Order components by mean (do NOT try to write back into gmmfit)
    [mu_sorted, ord] = sort(gmmfit.mu(:)); %#ok<ASGLU>  % ord maps low→high mean
    % If you want for logging:
    % sigma_sorted = sqrt(gmmfit.Sigma(:,:,ord));
    % w_sorted     = gmmfit.ComponentProportion(ord);

    % Posterior in original order, then pick the lower-mean column
    post = posterior(gmmfit, TSNR_vox);     % N×2
    p_noise = post(:, ord(1));              % probability of lower-mean comp

  

    TSNR_vox_noisy = zeros(size(TSNR_vox));
    index_noisy=find(p_noise > thr);
    TSNR_vox_noisy(index_noisy) = TSNR_vox(index_noisy);
    Mask_noisy=zeros(size(mask));
    ind=find(mask);
    for i=1:length(TSNR_vox);
        if TSNR_vox_noisy(i)>0
            Mask_noisy(ind(i))=1;
        end
    end
    
   % TSNR_vox_noisy = reshape(noisy_vec, size(mask));

    fprintf("FIACH: Noisy voxels segmented (thr=%.2f)\n", thr);
end

% function fiach_check_tsnr(TSNR_vol, Mask_noisy)
%     fprintf(' - Displaying TSNR maps...\n');
%     figure; montage(reshape(TSNR_vol,[size(TSNR_vol,1) size(TSNR_vol,2) 1 size(TSNR_vol,3)]),[0 100]); axis image off; colormap parula; colorbar; title('TSNR');
%     figure; montage(reshape(Mask_noisy,[size(Mask_noisy,1) size(Mask_noisy,2) 1 size(Mask_noisy,3)]),[0 1]); axis image off; colormap gray; colorbar; title('Noisy Voxels (mask)');
% end
function fiach_check_tsnr(TSNR_vol, Mask_noisy)
    fprintf(' - Displaying TSNR maps...\n');

    z = round(size(TSNR_vol,3)/2);

    figure;
    set(gcf, 'Visible', 'off');
    imagesc(TSNR_vol(:,:,z));
    axis image off; colormap parula; colorbar;
    title('TSNR (mid slice)');
    saveas(gcf, fullfile(pwd, 'FIACH_TSNR_midslice.png'));
    close(gcf);

    figure;
    set(gcf, 'Visible', 'off');
    imagesc(Mask_noisy(:,:,z));
    axis image off; colormap gray; colorbar;
    title('Noisy Voxels (mid slice)');
    saveas(gcf, fullfile(pwd, 'FIACH_NoisyMask_midslice.png'));
    close(gcf);
end



function [pca_coeff, pca_score, pca_latent, pca_tsquared, pca_explained] = NoisyPCA(vol, TSNR_noisy_mask)
% Take up to the first 6 PCs of noisy voxels' time series (observations = time)

    fprintf("\nFIACH: Finding principal components of noisy voxels...\n");

    volSize  = size(vol);
    nFrames  = volSize(4);

    tmp_noise_mask = TSNR_noisy_mask(:);        % logical vector DC corrected - 
    if ~any(tmp_noise_mask)
        warning('NoisyPCA:EmptyMask','No noisy voxels; returning empty outputs.');
        pca_coeff = []; pca_score = []; pca_latent = []; pca_tsquared = []; pca_explained = [];
        return
    end

    tmp_vol = reshape(vol, [], nFrames);        % [Nvox_all × T]
    TSNR_noisy_timeseries = tmp_vol(find(tmp_noise_mask), :);  % [Nnoisy × T] DC corrected

    % Remove constant/NaN voxels to avoid rank issues
    bad = ~all(isfinite(TSNR_noisy_timeseries), 2) | (std(TSNR_noisy_timeseries,0,2) == 0);
    if any(bad)
        TSNR_noisy_timeseries = TSNR_noisy_timeseries(~bad, :);
    end
    if isempty(TSNR_noisy_timeseries)
        warning('NoisyPCA:NoValidVoxels','All noisy-voxel series invalid or constant; returning empty.');
        pca_coeff = []; pca_score = []; pca_latent = []; pca_tsquared = []; pca_explained = [];
        return
    end

    % Observations = time; Variables = voxels
    X = TSNR_noisy_timeseries.';                % [T × Nnoisy]

    k = min([6, size(X,1), size(X,2)]);        % can’t exceed rank
    [pca_coeff, pca_score, pca_latent, pca_tsquared, pca_explained] = ...
        pca(X, 'NumComponents', k);            % centers columns by default

    fprintf("FIACH: Noisy voxel PCA complete (k=%d)\n", k);
end

function sig_large_diff = LargeTempChanges(vol, mask, TE, threshold, nMads)
% Find frames with excessive frame-to-frame signal change.
% threshold: percent (%) max plausible change; if empty, derive from SigDiff.

    fprintf("FIACH: Identifying excessive signal changes\n");

    % Basic checks
    if ~islogical(mask), mask = logical(mask); end
    if ~isequal(size(mask), size(vol(:,:,:,1)))
        error('LargeTempChanges:MaskSize', 'Mask size must match volume spatial size.');
    end

    volSize = size(vol);
    nFrames = volSize(4);

    % |Δ| across time (detect spikes and drops)
    volDiff = abs(diff(vol, 1, 4));      % [X Y Z T-1]

    % Predicted maximum change (in %), then to fraction
    if isempty(threshold)
        R2Activation = R2Star(1.5, 110, 0.9);
        R2Baseline   = R2Star(1.5,  55, 0.6);
        diffMaxPct   = max(SigDiff(TE, R2Activation, R2Baseline));  % e.g. ~2.16
    else
        diffMaxPct   = threshold;
    end
    fprintf('FIACH: Predicted maximum signal change (%%): %.2f\n', diffMaxPct);
    diffMaxFrac = diffMaxPct / 100;

    % Robust scale per voxel across time (MAD), same unit as vol
    mads = mad(vol, 1, 4);  % [X Y Z 1]
    mads(~isfinite(mads)) = 0;

    % Allocate output (flag frame t when Δ(t-1->t) is too large)
    sig_large_diff = false(volSize);
    for t = 1:(nFrames-1)
        % Intensity-based threshold: fractional part + n*MAD
        maxDiff = (vol(:,:,:,t) * diffMaxFrac) + nMads * mads(:,:,:,1);
        bigJump = (volDiff(:,:,:,t) > maxDiff) & mask;
        sig_large_diff(:,:,:,t+1) = bigJump;
    end

    fprintf("FIACH: Large signal changes identified\n");
end

function [corrected_vol, voxels_changed] = InterpLargeChanges(vol, Bad_data, do_spline, spline_points)
% Interpolate flagged samples using either spline/pchip from neighbours
% or a robust per-voxel median fallback.

    fprintf("FIACH: Correcting large signal changes\n");

    volSize = size(vol);
    nFrames = volSize(4);

    X = reshape(vol, [], nFrames);          % [Nvox × T]
    B = reshape(Bad_data, [], nFrames);     % [Nvox × T]
    N = size(X,1);

    % Per-voxel robust fallback
    med_all = median(X, 2, 'omitnan');
    med_all(~isfinite(med_all)) = 0;

    voxels_changed = 0;

    for i = 1:N
        t = 1;
        while t <= nFrames
            if ~B(i,t)
                t = t + 1;
                continue
            end

            % Find run of consecutive bad samples starting at t
            t0 = t;
            while t <= nFrames && B(i,t)
                t = t + 1;
            end
            t1 = t - 1;         % inclusive end of the run
            runLen = t1 - t0 + 1;

            if runLen > 1
                % Multi-sample run: robust fallback (median of the voxel)
                X(i, t0:t1) = med_all(i);
                voxels_changed = voxels_changed + runLen;
                continue
            end

            % Single bad sample at t0: try to interpolate from neighbours
            left  = t0-1;
            right = t0+1;

            % Find nearest good left/right samples
            while left >= 1  && B(i,left),  left  = left  - 1; end
            while right <= nFrames && B(i,right), right = right + 1; end

            if left >= 1 && right <= nFrames
                if do_spline
                    % Use local window (good points only) and pchip/spline
                    L = max(1,  t0 - spline_points);
                    R = min(nFrames, t0 + spline_points);
                    idx = L:R;
                    idx(idx==t0) = [];         % drop center
                    good = ~B(i, idx);
                    idx  = idx(good);
                    if numel(idx) >= 2
                        % pchip avoids overshoot; swap to 'spline' if you prefer
                        X(i,t0) = interp1(idx, X(i,idx), t0, 'pchip');
                    else
                        X(i,t0) = (X(i,left) + X(i,right)) / 2;  % linear between neighbours
                    end
                else
                    X(i,t0) = (X(i,left) + X(i,right)) / 2;      % linear between nearest neighbours
                end
            else
                % At edges or no neighbours: robust fallback
                X(i,t0) = med_all(i);
            end

            voxels_changed = voxels_changed + 1;
            % (t already points to t0+1 here)
        end
    end

    pct = 100 * voxels_changed / numel(X);
    fprintf("FIACH: Large signal changes corrected, %d datapoints changed (%.3f %%)\n", ...
        voxels_changed, pct);

    corrected_vol = reshape(X, volSize);
end

function r2s = R2Star(B0, CBF, Y)
% R2* model with simple intravascular/intrinsic terms.
% Inputs:
%   B0  : field (T)
%   CBF : cerebral blood flow (ml/100g/min)  [empirical BVF approx uses this]
%   Y   : blood oxygen saturation fraction (0..1)
%
% Output:
%   r2s : s^-1

    % Constants
    gamma_Hz = 42.577e6;        % proton gyromagnetic ratio [Hz/T]
    Hct      = 0.40;            % hematocrit
    deltaChi0 = 0.27e-6;        % susceptibility difference (dimensionless, ~0.27 ppm)
    fgeom    = 1/3;             % geometric factor (sphere approx)

    % Blood volume fraction (empirical; your original formula)
    BVF = (0.8 * CBF^0.38) / 100;   % fraction (0..1)

    % Characteristic frequency shift (Hz)
    % (Some formulations use 4/3*pi; here we use a common 1/3 factor.)
    delta_f = gamma_Hz * B0 * deltaChi0 * Hct * (1 - Y) * fgeom; % Hz

    % Baseline R2 (s^-1): your empirical linear fit
    r2_base = 1.74 * B0 + 7.77;

    % R2' term proportional to BVF * frequency spread (still s^-1 scale)
    % We keep proportionality = 1 in Hz units (1/s). This is a simplification,
    % but adequate for producing a realistic percent-change cap downstream.
    r2_prime = BVF * delta_f;   % s^-1 (since Hz = 1/s)

    r2s = r2_base + r2_prime;
end

function S = Signal(TE, R2s)
% Mono-exponential signal model with S0 = 1
% TE in seconds, R2s in s^-1
    S = exp(-TE .* R2s);
end

function sPct = SigDiff(TE, R2Activation, R2Baseline)
% Percent absolute change between activation and baseline signals (S0 = 1)
% Returned in percent (%), consistent with LargeTempChanges usage.
    Sa = Signal(TE, R2Activation);
    Sb = Signal(TE, R2Baseline);
    sPct = 100 * abs(Sa - Sb);      % % of S0 (since S0=1)
end


% --------------------------------
% HELPER FUNCTIONS
% --------------------------------

function runs = list_runs(cfg)
    % Return struct array with .name (e.g. 'run-01') and .path (full file)
    files = cellstr(spm_select('FPList', cfg.dirEPIs, '^sub-.*_bold\.nii$'));
    if isempty(files)
        files = cellstr(spm_select('FPList', cfg.dirEPIs, '^sub.*bold\.nii$')); % fallback
    end
    assert(~isempty(files), 'No BOLD NIfTIs found in %s', cfg.dirEPIs);

    runs = struct('name', {}, 'path', {});
    for i = 1:numel(files)
        [~, fn, ~] = fileparts(files{i});
        tok = regexp(fn, '(run-\d+)', 'tokens', 'once');
        if isempty(tok), rname = sprintf('run-%02d', i); else, rname = tok{1}; end
        runs(end+1) = struct('name', rname, 'path', files{i}); %#ok<AGROW>
    end
end

function frames = expand_4d_frames(filepath)
    % Return char array of 'file.nii,<t>' rows for all frames in a 4D NIfTI
    V = spm_vol(filepath); 
    nT = numel(V);
    C = cell(nT,1);
    for t = 1:nT
        C{t} = sprintf('%s,%d', filepath, t);   % <-- use { } not [ ]
    end
    frames = char(C);
end

function [TR_s, TE_s, B0_T, nslices, TA_s, slice_order] = init_scan_params(cfg, useDicom)
    % --- TR/TE from DICOM (optional) or defaults ---
    if useDicom
        try
            [TR_s, TE_s, B0_T, ~] = read_scan_params_from_dicom_archives(cfg);
            fprintf('Using TR=%.3fs, TE=%.1fms, B0=%.1fT\n', TR_s, TE_s*1000, B0_T);
        catch ME
            warning('[%s] DICOM read failed: %s. Falling back to defaults.', ...
                    cfg.sName, ME.message);
            TR_s = 2.16; TE_s = 0.025; B0_T = NaN;
        end
    else
        % TR_s = 2.16; TE_s = 0.025; B0_T = NaN;
        TR_s = 1.25; TE_s = 0.025; B0_T = NaN;
    end

    % --- Nslices from first EPI; TA = TR - TR/Nslices ---
    epi4d = spm_select('FPList', cfg.dirEPIs, '^sub-.*_ses-.*_bold\.nii$');
    if isempty(epi4d)
        epi4d = spm_select('FPList', cfg.dirEPIs, '^sub.*bold\.nii$'); % fallback
    end
    assert(~isempty(epi4d), '[%s] No EPI 4D found in %s', cfg.sName, cfg.dirEPIs);

    Vepi = spm_vol(deblank(epi4d(1,:)));
    nslices = Vepi(1).dim(3);
    TA_s = TR_s - (TR_s / nslices);
    fprintf('Nslices=%d  →  TA=%.3fs\n', nslices, TA_s);

    % --- Slice order (try DICOM; else fallback) ---
    if useDicom
        slice_order = try_read_slice_order_from_dicoms(cfg, nslices);
    else
        slice_order = [];
    end
    if isempty(slice_order)
        slice_order = nslices:-1:1;  % fallback: descending
    end

end

function [TR_s, TE_s, B0_T, seriesInfo] = read_scan_params_from_dicom_archives(cfg)
% Find TR/TE/B0 for the EPI/BOLD series by scanning all .tar.bz2 under <cfg.sDir>/DICOM/**

    dcmRoot  = fullfile(cfg.sDir, 'DICOM');
    A = dir(fullfile(dcmRoot, '**', '*.tar.bz2'));
    if isempty(A), error('No .tar.bz2 archives under %s', dcmRoot); end

    % skip AppleDouble and tiny sidecars
    A = A(~startsWith({A.name}, '._') & [A.bytes] > 1024);

    epiKeys  = ["epi","bold","rest","func","mb","ep_bold","fmri"];
    skipKeys = ["localiser","localizer","survey","scout","t1","mprage","calibr","fieldmap","gre"];

    for ai = 1:numel(A)
        archPath = fullfile(A(ai).folder, A(ai).name);
        % quick name pre-filter
        low = lower(archPath);
        if any(contains(low, skipKeys)) && ~any(contains(low, epiKeys))
            continue
        end

        tmpDir = fullfile(tempdir, ['dicompeek_' char(java.util.UUID.randomUUID)]);
        mkdir(tmpDir)
        extracted = false;
        try
            untar(archPath, tmpDir); extracted = true;
        catch
            if ~ispc
                [ok1,~] = system(sprintf('tar -x -j -f "%s" -C "%s"', archPath, tmpDir)); %#ok<ASGLU>
                extracted = (ok1==0);
            end
        end
        if ~extracted, cleanup(tmpDir); continue; end

        % look at up to N files to find a representative DICOM header
        files = dir(fullfile(tmpDir, '**', '*'));
        files = files(~[files.isdir]);
        N = min(50, numel(files));
        info = [];
        for k = 1:N
            f = fullfile(files(k).folder, files(k).name);
            try
                info = dicominfo(f);
            catch, info = []; end
            if ~isempty(info)
                % classify: EPI if series/protocol/image/sequence mentions it
                sdesc = lower(getf(info,'SeriesDescription',''));
                prot  = lower(getf(info,'ProtocolName',''));
                itype = lower(strjoin(string(getf(info,'ImageType',{})))); % can be cell or string
                sseq  = lower(getf(info,'ScanningSequence',''));
                sname = lower(getf(info,'SequenceName',''));

                isEPI = any(contains([sdesc prot itype sseq sname], epiKeys));
                isSkip= any(contains([sdesc prot], skipKeys));

                if isEPI && ~isSkip
                    % pull values (guard ms vs s)
                    TR = double(getf(info,'RepetitionTime',NaN));
                    TE = double(getf(info,'EchoTime',NaN));
                    TR_s = TR; if ~isnan(TR_s) && TR_s >= 50, TR_s = TR_s/1000; end
                    TE_s = TE; if ~isnan(TE_s) && TE_s >= 1,  TE_s = TE_s/1000; end
                    B0_T = double(getf(info,'MagneticFieldStrength',NaN));

                    seriesInfo = struct( ...
                        'SeriesDescription', string(getf(info,'SeriesDescription',"")), ...
                        'ProtocolName',      string(getf(info,'ProtocolName',"")), ...
                        'FlipAngle',         getf(info,'FlipAngle',NaN), ...
                        'Manufacturer',      string(getf(info,'Manufacturer',"")), ...
                        'Archive',           string(archPath) );

                    fprintf('[%s] EPI params → TR=%.3f s, TE=%.1f ms, B0=%.1f T, Series="%s"\n', ...
                        cfg.sName, TR_s, TE_s*1000, B0_T, seriesInfo.SeriesDescription);

                    cleanup(tmpDir);
                    return
                end
            end
        end
        cleanup(tmpDir);
    end

    error('No EPI-like series found under %s', dcmRoot);
end

function v = getf(S, fld, default)
    if isfield(S,fld), v = S.(fld); else, v = default; end
end

function cleanup(p)
    if exist(p,'dir'), rmdir(p,'s'); end
end

function QC_LargeTempChanges(vol_before, vol_after, Bad_data)
    % QC_LargeTempChanges - diagnostics for temporal spike correction
    %
    % Inputs:
    %   vol_before - 4D before correction
    %   vol_after  - 4D after correction
    %   Bad_data   - logical mask [X Y Z T] of flagged points

    fprintf('Running QC for LargeTempChanges...\n');

    % 1) Frames affected
    bad_by_frame = squeeze(any(Bad_data, [1 2 3]));  
    fprintf('Frames with any correction: %d / %d (%.1f%%)\n', ...
        nnz(bad_by_frame), numel(bad_by_frame), ...
        100*nnz(bad_by_frame)/numel(bad_by_frame));

    % 2) Per-voxel burden
    bad_counts_vox = squeeze(sum(Bad_data, 4));    
    fprintf('Median / 95th percentile voxel corrections: %.0f / %.0f frames\n', ...
        median(bad_counts_vox(:)), prctile(bad_counts_vox(:),95));

    % 3) Plot % of voxels corrected per frame
    pct_vox_per_frame = squeeze(sum(Bad_data,[1 2 3])) ./ prod(size(Bad_data,1:3)) * 100;
    figure;
    set(gcf, 'Visible', 'off');
    plot(pct_vox_per_frame);
    xlabel('Frame'); ylabel('% voxels corrected'); 
    title('Voxel corrections per frame');
    saveas(gcf, fullfile(pwd, 'FIACH_QC_corrections_per_frame.png'));
    close(gcf);

    % 4) Example traces for worst voxels
    [~, idx] = maxk(bad_counts_vox(:), 3);
    for k = 1:numel(idx)
        [i,j,l] = ind2sub(size(bad_counts_vox), idx(k));
        s1 = squeeze(vol_before(i,j,l,:));
        s2 = squeeze(vol_after(i,j,l,:));
        % save figure:
        figure;
        set(gcf, 'Visible', 'off');
        plot([s1 s2]); legend('before','after');
        title(sprintf('Voxel [%d %d %d]',i,j,l));
        saveas(gcf, fullfile(pwd, sprintf('FIACH_QC_worstvoxel_%d.png', k)));
        close(gcf);
    end
end

function save_4d_nifti(vol4d, Vref, outPath)
    % Save a 4D volume (X×Y×Z×T) as a single 4D NIfTI using SPM12.
    %
    % vol4d   : numeric (X×Y×Z×T)
    % Vref    : SPM vol struct (from spm_vol); if array, use Vref(1)
    % outPath : '/path/rclean_SUBJ.nii'

    if numel(Vref) > 1, Vref = Vref(1); end

    [nx, ny, nz, nt] = size(vol4d);

    % Optional sanity check against reference header
    if isfield(Vref, 'dim') && ~isequal([nx ny nz], Vref.dim)
        warning('save_4d_nifti:DimMismatch', ...
            'vol4d spatial dims [%d %d %d] ≠ Vref.dim [%d %d %d]. Writing anyway.', ...
            nx, ny, nz, Vref.dim(1), Vref.dim(2), Vref.dim(3));
    end

    % Overwrite if exists (avoid stale headers)
    if exist(outPath, 'file'), delete(outPath); end

    % Base header from reference
    Vtmpl        = Vref;
    Vtmpl.fname  = outPath;
    Vtmpl.dt     = [spm_type('float32') spm_platform('bigend')];  % float32
    Vtmpl.pinfo  = [1; 0; 0];                                     % no scaling

    % Pre-create each 3D frame header in the same 4D file
    Vouts = repmat(Vtmpl, nt, 1);
    for t = 1:nt
        Vouts(t).n = [t 1];               % t-th frame in 4D
        Vouts(t)   = spm_create_vol(Vouts(t));
    end

    % Write data frame-by-frame (cast to single to match dt)
    for t = 1:nt
        spm_write_vol(Vouts(t), single(vol4d(:,:,:,t)));
    end

    fprintf('Saved 4D NIfTI with %d frames → %s\n', nt, outPath);
end

