function compare_csi(files, labels, tWin)
% COMPARE_CSI  Compare CSI amplitude across scenarios, side by side.
%   compare_csi()                                   % default E00/E01/E02 trial01, 5-15s
%   compare_csi(files, labels, [5 15])
%
% files : cell array of CSV paths (from capture_csi.py)
% labels: cell array of scenario names (same length)
% tWin  : [t0 t1] seconds to keep (default [5 15], i.e. drop first 5 s)
%
% Amplitude A_k(t) = sqrt(I^2 + Q^2),  A : [time x subcarrier].
% Figure 1: amplitude heatmaps (1 x N), shared color scale.
% Figure 2: mean / std over subcarriers, and PCA 1st component (3 x N),
%           y-axis shared within each row for fair comparison.

    if nargin < 1 || isempty(files)
        repo = fileparts(fileparts(mfilename('fullpath')));   % repo root (parent of matlab/)
        files = {fullfile(repo,'results','E00_static_20s_trial02.csv'), ...
                 fullfile(repo,'results','E01_hand_in_static_trial02.csv'), ...
                 fullfile(repo,'results','E02_hand_waving_trial02.csv')};
    end
    if nargin < 2 || isempty(labels)
        labels = {'E00 static', 'E01 hand-in-static', 'E02 hand-waving'};
    end
    if nargin < 3 || isempty(tWin), tWin = [5 20]; end

    n = numel(files);
    A = cell(n,1); T = cell(n,1); S = cell(n,1); P = cell(n,1);

    fprintf('\n--- window %g..%g s ---\n', tWin(1), tWin(2));
    for i = 1:n
        [Ai, ti] = load_amp(files{i});
        m  = ti >= tWin(1) & ti <= tWin(2);
        Ai = Ai(m,:);  ti = ti(m);
        dt = diff(ti)*1000;                                   % ms
        rate = (numel(ti)-1) / (ti(end)-ti(1));
        fprintf('%-22s : %4d pkts, rate=%.1f Hz, median dt=%.2f ms, gaps>2x median=%d\n', ...
                labels{i}, numel(ti), rate, median(dt), nnz(dt > 2*median(dt)));
        % fill any NaN padding with that subcarrier's mean
        cm = mean(Ai,1,'omitnan'); [r,c] = find(isnan(Ai));
        for q = 1:numel(r), Ai(r(q),c(q)) = cm(c(q)); end
        A{i} = Ai; T{i} = ti;
        S{i} = std(Ai,0,2);
        Ac = Ai - mean(Ai,1); [U,Sv,~] = svd(Ac,'econ'); P{i} = U(:,1)*Sv(1,1);
    end
    ncols = size(A{1},2);

    % shared robust color limits (drop near-zero guard/DC bins, clip k=1 outlier)
    allv = []; for i=1:n, v=A{i}(:); allv=[allv; v(isfinite(v)&v>1)]; end %#ok<AGROW>
    cl = [prctile(allv,1) prctile(allv,99)];

    %% Figure 1: heatmaps, scenarios side by side
    figure('Color','w','Name','CSI amplitude heatmaps');
    tl = tiledlayout(1, n, 'TileSpacing','compact', 'Padding','compact');
    for i = 1:n
        nexttile;
        imagesc(T{i}, 1:ncols, A{i}'); set(gca,'YDir','normal'); clim(cl);
        title(labels{i}); xlabel('time [s]');
        if i==1, ylabel('subcarrier index k'); end
    end
    colormap(parula);
    cb = colorbar; cb.Layout.Tile = 'east'; cb.Label.String = 'amplitude |H_k(t)|';
    title(tl, sprintf('CSI amplitude A_k(t)  (t = %g..%g s, shared color scale)', tWin(1), tWin(2)));

    %% Figure 2: std / PC1, scenarios side by side (y shared per row)
    figure('Color','w','Name','CSI summary metrics');
    nrow = 2;
    tiledlayout(nrow, n, 'TileSpacing','compact', 'Padding','compact');
    rows = {S, 'std_k A'; P, 'PC1 score'};
    ax = gobjects(nrow, n);
    for rr = 1:nrow
        for i = 1:n
            ax(rr,i) = nexttile((rr-1)*n + i);
            plot(T{i}, rows{rr,1}{i}, 'LineWidth', 0.8); grid on;
            if i==1, ylabel(rows{rr,2}); end
            if rr==1, title(labels{i}); end
            if rr==nrow, xlabel('time [s]'); end
        end
        linkaxes(ax(rr,:), 'y');     % same y-scale across scenarios in this row
    end
end

% ---- local: load amplitude matrix + relative time (s) from a capture CSV ----
function [A, tSec] = load_amp(csvfile)
    lines = readlines(csvfile);
    lines = lines(startsWith(lines, "CSI_DATA"));
    if isempty(lines), error('No CSI_DATA rows in %s', csvfile); end
    n = numel(lines); ac = cell(n,1); ts = nan(n,1); nc = 0;
    for i = 1:n
        ln = lines(i);
        tok = regexp(ln, '\[(.*)\]', 'tokens', 'once'); if isempty(tok), continue; end
        raw = sscanf(tok{1}, '%d')'; n2 = 2*floor(numel(raw)/2);
        im = double(raw(1:2:n2)); re = double(raw(2:2:n2));
        ac{i} = sqrt(im.^2 + re.^2); nc = max(nc, numel(ac{i}));
        p = split(ln, ','); if numel(p) >= 19, ts(i) = str2double(p(19)); end
    end
    A = nan(n, nc);
    for i = 1:n, if ~isempty(ac{i}), A(i,1:numel(ac{i})) = ac{i}; end, end
    valid = ~isnan(ts); A = A(valid,:); tv = ts(valid); tSec = (tv - tv(1))/1e6;
end
