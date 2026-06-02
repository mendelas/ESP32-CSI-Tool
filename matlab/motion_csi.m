function motion_csi(files, labels, tWin, win)
% MOTION_CSI  Moving-variance motion score from CSI amplitude.
%   motion_csi()                          % E00/E01/E02 trial02, 5-20s, 0.5s window
%   motion_csi(files, labels, [5 20], 0.1)
%
% Pipeline (amplitude only):
%   A_k(t) = |H_k(t)| = sqrt(I^2 + Q^2)
%   Z_k(t) = (A_k(t) - mean(A_k)) / std(A_k)         % per-subcarrier standardization
%   motion_score(t) = mean_k  Var_window( Z_k(t) )   % moving variance, averaged over k
%
% Larger motion_score => stronger temporal fluctuation => motion.
% Expected: E00 static low; E01 spikes when hand enters/leaves; E02 sustained high.
% Near-constant subcarriers (guard/DC, std~0) are excluded from standardization.

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
    score = cell(n,1); T = cell(n,1);

    fprintf('\n--- motion_score (window %g..%g s, moving var %.2f s) ---\n', tWin(1), tWin(2), win);
    for i = 1:n
        [A, ti] = load_amp(files{i});
        m = ti >= tWin(1) & ti <= tWin(2);
        A = A(m,:); ti = ti(m);
        cm = mean(A,1,'omitnan'); [r,c] = find(isnan(A));
        for q = 1:numel(r), A(r(q),c(q)) = cm(c(q)); end

        % per-subcarrier z-score; drop near-constant (guard/DC) subcarriers
        mu = mean(A,1);  sd = std(A,0,1);
        keep = sd > 0.05*median(sd(sd>0));
        Z = (A(:,keep) - mu(keep)) ./ sd(keep);

        rate = (numel(ti)-1) / (ti(end)-ti(1));
        w    = max(3, round(win*rate));
        V    = movvar(Z, w, 0, 1);            % moving variance along time  [T x Kkeep]
        ms   = mean(V, 2);                    % motion_score(t)

        score{i} = ms; T{i} = ti;
        fprintf('%-22s : mean motion_score = %.3f   (p95 = %.3f, max = %.3f)\n', ...
                labels{i}, mean(ms), prctile(ms,95), max(ms));
    end

    %% motion_score(t), scenarios overlaid
    figure('Color','w','Name','CSI motion score');
    hold on;
    for i = 1:n, plot(T{i}, score{i}, 'LineWidth', 1.0); end
    hold off; grid on; legend(labels, 'Location','best');
    xlabel('time [s]'); ylabel('motion\_score(t) = mean_k Var_{win}(Z_k)');
    title(sprintf('Motion score (per-subcarrier z-score, %.2f s moving variance)', win));
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
