function A = plot_csi(csvfile)
% PLOT_CSI  Amplitude analysis of a captured CSI CSV.
%   A = plot_csi('results/E02_hand_waving_trial01.csv')
%
% CSV is produced by python_utils/capture_csi.py.
% Each data row ends with the bracketed CSI array [I Q I Q ...] (int8, interleaved):
%   H_k(t) = I_k(t) + j*Q_k(t)   ->   amplitude A_k(t) = sqrt(I^2 + Q^2)
%
% Returns A : [time samples x subcarriers].
% First prints timing/rate/dropout stats, then shows the amplitude heatmap
% imagesc(A')  (y = subcarrier, x = time), followed by mean/std/PCA1 over time.

    if nargin < 1 || isempty(csvfile)
        csvfile = 'results/exp.csv';
    end

    %% ---- parse ----
    lines = readlines(csvfile);
    lines = lines(startsWith(lines, "CSI_DATA"));
    if isempty(lines)
        error('No CSI_DATA rows found in %s', csvfile);
    end
    nPkt = numel(lines);

    ampCell = cell(nPkt, 1);
    localTs = nan(nPkt, 1);          % local_timestamp [microseconds], field 19
    ncols   = 0;
    for i = 1:nPkt
        ln  = lines(i);
        tok = regexp(ln, '\[(.*)\]', 'tokens', 'once');
        if isempty(tok), continue; end
        raw = sscanf(tok{1}, '%d')';
        n2  = 2*floor(numel(raw)/2);
        im  = double(raw(1:2:n2));
        re  = double(raw(2:2:n2));
        a   = sqrt(im.^2 + re.^2);   % A_k(t)
        ampCell{i} = a;
        ncols = max(ncols, numel(a));
        parts = split(ln, ',');
        if numel(parts) >= 19, localTs(i) = str2double(parts(19)); end
    end

    A = nan(nPkt, ncols);            % [time x subcarrier]
    for i = 1:nPkt
        a = ampCell{i};
        if ~isempty(a), A(i,1:numel(a)) = a; end
    end

    %% ---- timing / sampling-rate / dropout report (print only) ----
    ts = localTs;
    valid = ~isnan(ts);
    fprintf('\n===== %s =====\n', csvfile);
    fprintf('packets         : %d\n', nPkt);
    fprintf('subcarriers     : %d\n', ncols);
    if nnz(valid) > 1
        tv    = ts(valid);
        spanS = (tv(end) - tv(1)) / 1e6;          % local_timestamp is microseconds
        rate  = (numel(tv) - 1) / spanS;
        dtMs  = diff(tv) / 1e3;
        expMs = 1000 / rate;
        bigGap = dtMs > 2*median(dtMs);           % dropout indicator (> 2x typical)
        fprintf('span            : %.2f s\n', spanS);
        fprintf('effective rate  : %.1f Hz\n', rate);
        fprintf('interval [ms]   : median=%.2f  mean=%.2f  std(jitter)=%.2f\n', ...
                median(dtMs), mean(dtMs), std(dtMs));
        fprintf('interval [ms]   : min=%.2f  p95=%.2f  max=%.2f  (target=%.2f)\n', ...
                min(dtMs), prctile(dtMs,95), max(dtMs), expMs);
        fprintf('large gaps (>2x median): %d  (%.1f%% of intervals), max gap=%.1f ms\n', ...
                nnz(bigGap), 100*mean(bigGap), max(dtMs));
        tSec = (tv - tv(1)) / 1e6;                 % time axis for plots (per valid pkt)
    else
        warning('Not enough timestamps for timing stats.');
        rate = NaN; tSec = (0:nPkt-1)';
    end
    fprintf('\n');

    %% ---- FIGURE 1 (primary): amplitude heatmap, subcarrier x time ----
    figure('Name', sprintf('CSI amplitude heatmap: %s', csvfile), 'Color', 'w');
    Aplot = A; if nnz(valid) > 1, Aplot = A(valid, :); end
    imagesc(tSec, 1:ncols, Aplot');               % imagesc(A') : x=time, y=subcarrier
    set(gca, 'YDir', 'normal');
    colormap(parula); cb = colorbar; cb.Label.String = 'amplitude  |H_k(t)|';
    % robust color limits: drop near-zero guard/DC bins and clip the k=1 outlier
    v = Aplot(:); v = v(isfinite(v) & v > 1);
    if ~isempty(v), clim([prctile(v,1) prctile(v,99)]); end
    xlabel('time [s]'); ylabel('subcarrier index k');
    title(sprintf('CSI amplitude A_k(t)  (%d packets, %d subcarriers, %.1f Hz)', ...
          nPkt, ncols, rate));

    %% ---- FIGURE 2 (follow-up): mean / std / PCA1 over time ----
    Af = A; if nnz(valid) > 1, Af = A(valid, :); end
    % fill any NaN (padding) with that subcarrier's mean so stats/PCA are well-defined
    cm = mean(Af, 1, 'omitnan');
    [r, c] = find(isnan(Af));
    for q = 1:numel(r), Af(r(q), c(q)) = cm(c(q)); end

    meanT = mean(Af, 2);                 % mean over subcarriers, per time sample
    stdT  = std(Af, 0, 2);               % std over subcarriers, per time sample
    Ac    = Af - mean(Af, 1);            % center each subcarrier over time
    [U, S, ~] = svd(Ac, 'econ');         % PCA via SVD (no toolbox needed)
    pc1   = U(:,1) * S(1,1);             % 1st principal component score over time

    figure('Name', sprintf('CSI summary: %s', csvfile), 'Color', 'w');
    tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
    nexttile; plot(tSec, meanT, 'LineWidth', 1);
        ylabel('mean_k A'); title('Mean amplitude over subcarriers'); grid on;
    nexttile; plot(tSec, stdT, 'LineWidth', 1, 'Color', [0.85 0.33 0.1]);
        ylabel('std_k A'); title('Std of amplitude over subcarriers (motion indicator)'); grid on;
    nexttile; plot(tSec, pc1, 'LineWidth', 1, 'Color', [0.47 0.25 0.8]);
        ylabel('PC1 score'); xlabel('time [s]'); title('1st principal component over time'); grid on;
end
