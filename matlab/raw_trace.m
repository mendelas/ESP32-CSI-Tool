function raw_trace(files, labels, ksel, tWin)
% RAW_TRACE  Ground-truth check: raw amplitude A_k(t) of a few strong subcarriers.
%   raw_trace()                              % E00/E01/E02 140cm trial01, auto subcarriers, 5-20s
%   raw_trace(files, labels, [10 20 40 50], [5 20])
%
% Plots raw A_k(t) = |H_k(t)| for a handful of strong subcarriers, scenarios
% side by side (rows = subcarrier, cols = scenario, y-axis shared per row).
% If hand motion is present in the data, the motion columns should visibly
% fluctuate more than the static column. No normalization, no filtering.

    if nargin < 1 || isempty(files)
        repo = fileparts(fileparts(mfilename('fullpath')));
        files = {fullfile(repo,'results','E00_static_15s_140cm_trial01.csv'), ...
                 fullfile(repo,'results','E01_hand_in_static_140cm_trial01.csv'), ...
                 fullfile(repo,'results','E02_hand_waving_140cm_trial01.csv')};
    end
    if nargin < 2 || isempty(labels)
        labels = {'E00 static', 'E01 hand-in-static', 'E02 hand-waving'};
    end
    if nargin < 4 || isempty(tWin), tWin = [5 20]; end

    n = numel(files);
    A = cell(n,1); T = cell(n,1);
    for i = 1:n
        [Ai, ti] = load_amp(files{i});
        m = ti >= tWin(1) & ti <= tWin(2);
        A{i} = Ai(m,:); T{i} = ti(m);
    end

    % choose strong subcarriers from the first scenario (exclude k=1 artifact & dead bins)
    if nargin < 3 || isempty(ksel)
        mu = mean(A{1}, 1, 'omitnan'); sd = std(A{1}, 0, 1, 'omitnan');
        mu(1) = -inf;                         % drop k=1 (DC/artifact)
        mu(sd < 0.05*median(sd(sd>0))) = -inf; % drop guard/DC (near-constant)
        [~, ord] = sort(mu, 'descend');
        ksel = sort(ord(1:min(4, sum(isfinite(mu)))));
    end
    fprintf('selected subcarriers: %s\n', mat2str(ksel));

    nk = numel(ksel);
    figure('Color','w','Name','Raw amplitude per subcarrier');
    tiledlayout(nk, n, 'TileSpacing','compact', 'Padding','compact');
    ax = gobjects(nk, n);
    for rr = 1:nk
        k = ksel(rr);
        for i = 1:n
            ax(rr,i) = nexttile((rr-1)*n + i);
            plot(T{i}, A{i}(:,k), 'LineWidth', 0.6);
            grid on;
            if rr == 1, title(labels{i}); end
            if i == 1, ylabel(sprintf('k=%d  |H|', k)); end
            if rr == nk, xlabel('time [s]'); end
        end
        linkaxes(ax(rr,:), 'y');     % same y-scale across scenarios for this subcarrier
    end
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
