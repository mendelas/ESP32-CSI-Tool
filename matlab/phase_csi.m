function phase_csi(csvfile, tWin, ksel)
% PHASE_CSI  Look at RAW CSI phase (unwrap only, no calibration/detrend).
%   phase_csi()                          % E02 hand-waving 140cm trial01, 5-20s
%   phase_csi('results/xxx.csv', [5 20], [18 19 21 40])
%
% phi_k(t) = atan2(IM_k, RE_k).  Unwrapped ACROSS subcarriers (per packet).
% No detrending, no offset removal -- this is the raw phase as captured.
%
% Figure 1: unwrapped phase vs subcarrier, several packets overlaid.
% Figure 2: unwrapped phase over time, a few subcarriers.

    if nargin < 1 || isempty(csvfile)
        repo = fileparts(fileparts(mfilename('fullpath')));
        csvfile = fullfile(repo,'results','E02_hand_waving_140cm_trial01.csv');
    end
    if nargin < 2 || isempty(tWin), tWin = [5 20]; end

    [IM, RE, ti] = load_iq(csvfile);
    m = ti >= tWin(1) & ti <= tWin(2);
    IM = IM(m,:); RE = RE(m,:); ti = ti(m);

    [T, K] = size(IM);
    phi  = atan2(IM, RE);              % raw wrapped phase (-pi, pi]
    phiU = unwrap(phi, [], 2);         % unwrap across subcarriers only

    if nargin < 3 || isempty(ksel)
        mA = mean(sqrt(IM.^2 + RE.^2), 1);
        mA(1) = -inf;                  % skip k=1 (DC/artifact)
        [~, ord] = sort(mA, 'descend');
        ksel = sort(ord(1:min(4, K-1)));
    end

    fprintf('\n%s\npackets=%d  subcarriers=%d  window=%g..%g s\n', csvfile, T, K, tWin(1), tWin(2));
    fprintf('selected subcarriers for time view: %s\n', mat2str(ksel));

    %% Figure 1: raw unwrapped phase vs subcarrier (several packets overlaid)
    idx = round(linspace(1, T, min(30, T)));
    figure('Color','w','Name','Raw unwrapped phase vs subcarrier');
    plot(1:K, phiU(idx,:)', 'LineWidth', 0.4);
    grid on; xlabel('subcarrier index k'); ylabel('unwrapped phase [rad]');
    title(sprintf('Raw unwrapped phase per packet (%d packets overlaid)', numel(idx)));

    %% Figure 2: raw unwrapped phase over time (one panel per subcarrier)
    nk = numel(ksel);
    figure('Color','w','Name','Raw unwrapped phase over time');
    tiledlayout(nk, 1, 'TileSpacing','compact', 'Padding','compact');
    for r = 1:nk
        nexttile;
        plot(ti, phiU(:, ksel(r)), 'LineWidth', 0.6); grid on;
        ylabel(sprintf('k=%d  [rad]', ksel(r)));
        if r == 1, title('Raw unwrapped phase \phi_k(t) over time'); end
        if r == nk, xlabel('time [s]'); end
    end

    %% Figure 3: variance of the WRAPPED phase over time, per subcarrier
    vp = var(phi, 0, 1);                     % var over time of wrapped phase, per k
    figure('Color','w','Name','Wrapped-phase variance per subcarrier');
    plot(1:K, vp, 'o-', 'LineWidth', 1, 'MarkerSize', 3); grid on; hold on;
    yline(pi^2/3, 'r--', '\pi^2/3 (uniform-random level)', 'LineWidth', 1);
    hold off;
    xlabel('subcarrier index k'); ylabel('var_t(\phi_k)  [rad^2]');
    title('Variance of WRAPPED phase over time (per subcarrier)');
    fprintf('wrapped-phase var over time: median=%.2f rad^2 (uniform-random = %.2f)\n', ...
            median(vp), pi^2/3);
end

% ---- local: imag/real matrices [time x subcarrier] + relative time (s) ----
function [IM, RE, tSec] = load_iq(csvfile)
    lines = readlines(csvfile);
    lines = lines(startsWith(lines, "CSI_DATA"));
    if isempty(lines), error('No CSI_DATA rows in %s', csvfile); end
    n = numel(lines); imc = cell(n,1); rec = cell(n,1); ts = nan(n,1); nc = 0;
    for i = 1:n
        ln = lines(i);
        tok = regexp(ln, '\[(.*)\]', 'tokens', 'once'); if isempty(tok), continue; end
        raw = sscanf(tok{1}, '%d')'; n2 = 2*floor(numel(raw)/2);
        imc{i} = double(raw(1:2:n2));   % imaginary (even index, like parse_csi.py)
        rec{i} = double(raw(2:2:n2));   % real
        nc = max(nc, numel(imc{i}));
        p = split(ln, ','); if numel(p) >= 19, ts(i) = str2double(p(19)); end
    end
    IM = nan(n, nc); RE = nan(n, nc);
    for i = 1:n
        if ~isempty(imc{i})
            IM(i,1:numel(imc{i})) = imc{i};
            RE(i,1:numel(rec{i})) = rec{i};
        end
    end
    valid = ~isnan(ts); IM = IM(valid,:); RE = RE(valid,:); tv = ts(valid); tSec = (tv - tv(1))/1e6;
end
