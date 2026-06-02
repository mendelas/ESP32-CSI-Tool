function motion_csi(files, labels, tWin, win)
% MOTION_CSI  Moving-variance motion score from CSI amplitude.
%   motion_csi()                          % E00/E01/E02 trial02, 5-20s, 0.5s window
%   motion_csi(files, labels, [5 20], 0.1)
%
% Pipeline (amplitude only):
%   A_k(t) = |H_k(t)| = sqrt(I^2 + Q^2)
%   R_k(t) = A_k(t) / mean(A_k)                       % per-subcarrier MEAN-normalization
%   motion_score(t) = mean_k  std_window( R_k(t) )    % moving std, averaged over k
%
% Larger motion_score => stronger temporal fluctuation => motion.
% Expected: E00 static low; E01 spikes when hand enters/leaves; E02 sustained high.
% Note: we divide by the MEAN (a constant), NOT the std. Dividing by std would
% absorb slow motion into the denominator and suppress it (the earlier issue).
% Near-constant subcarriers (guard/DC, std~0) are excluded.

    if nargin < 1 || isempty(files)
        repo = fileparts(fileparts(mfilename('fullpath')));   % repo root (parent of matlab/)
        files = {fullfile(repo,'results','E00_static_15s_140cm_trial01.csv'), ...
                 fullfile(repo,'results','E01_hand_in_static_140cm_trial01.csv'), ...
                 fullfile(repo,'results','E02_hand_waving_140cm_trial01.csv')};
    end
    if nargin < 2 || isempty(labels)
        labels = {'E00 static', 'E01 hand-in-static', 'E02 hand-waving'};
    end
    if nargin < 3 || isempty(tWin), tWin = [5 20]; end
    if nargin < 4 || isempty(win),  win  = 0.5; end    % moving-window length [s]

    n = numel(files);
    score = cell(n,1); T = cell(n,1); Dmat = cell(n,1);

    fprintf('\n--- motion_score (window %g..%g s, moving std %.2f s) ---\n', tWin(1), tWin(2), win);
    for i = 1:n
        [A, ti] = load_amp(files{i});
        m = ti >= tWin(1) & ti <= tWin(2);
        A = A(m,:); ti = ti(m);
        cm = mean(A,1,'omitnan'); [r,c] = find(isnan(A));
        for q = 1:numel(r), A(r(q),c(q)) = cm(c(q)); end

        % per-subcarrier MEAN-normalization (fractional); drop near-constant bins
        mu = mean(A,1);  sd = std(A,0,1);
        keep = sd > 0.05*median(sd(sd>0));
        R = A(:,keep) ./ mu(keep);            % relative amplitude (dimensionless)

        rate = (numel(ti)-1) / (ti(end)-ti(1));
        w    = max(3, round(win*rate));
        ms   = mean(movstd(R, w, 0, 1), 2);   % motion_score(t) = avg fractional moving std

        D = A ./ mu - 1;                       % fractional deviation per subcarrier
        D(:, ~keep) = 0;                       % blank dead/guard bins
        score{i} = ms; T{i} = ti; Dmat{i} = D;
        fprintf('%-22s : mean motion_score = %.3f   (p95 = %.3f, max = %.3f)\n', ...
                labels{i}, mean(ms), prctile(ms,95), max(ms));
    end

    %% motion_score(t), scenarios overlaid
    figure('Color','w','Name','CSI motion score');
    hold on;
    for i = 1:n, plot(T{i}, score{i}, 'LineWidth', 1.0); end
    hold off; grid on; legend(labels, 'Location','best');
    xlabel('time [s]'); ylabel('motion\_score(t) = mean_k std_{win}(A_k/mean A_k)');
    title(sprintf('Motion score (mean-normalized, %.2f s moving std)', win));

    %% Figure 2: per-subcarrier fractional fluctuation heatmap (all subcarriers)
    K = size(Dmat{1}, 2);
    alld = [];
    for i = 1:n, v = Dmat{i}(:); alld = [alld; abs(v(isfinite(v)))]; end %#ok<AGROW>
    cl = prctile(alld, 99); if ~(cl > 0), cl = 1; end
    n2 = 128;                                   % blue(-) - white(0) - red(+)
    cmap = [ [linspace(0,1,n2)', linspace(0,1,n2)', ones(n2,1)]; ...
             [ones(n2,1), linspace(1,0,n2)', linspace(1,0,n2)'] ];
    figure('Color','w','Name','CSI fluctuation heatmaps');
    tl = tiledlayout(1, n, 'TileSpacing','compact', 'Padding','compact');
    for i = 1:n
        nexttile;
        imagesc(T{i}, 1:K, Dmat{i}'); set(gca,'YDir','normal'); clim([-cl cl]);
        title(labels{i}); xlabel('time [s]');
        if i == 1, ylabel('subcarrier index k'); end
    end
    colormap(cmap); cb = colorbar; cb.Layout.Tile = 'east';
    cb.Label.String = 'A_k/mean_k - 1';
    title(tl, 'Per-subcarrier fractional fluctuation  (static \approx white, motion = colored bands)');
end

% ---- local: amplitude matrix [time x subcarrier] + relative time (s) ----
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
