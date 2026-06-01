#!/usr/bin/env python3
"""
Plot CSI amplitude from a captured CSV (produced by capture_csi.py or
`grep CSI_DATA`). Saves a PNG instead of opening a GUI window.

Usage:
    python plot_csi.py [CSVFILE] [OUTPNG]
Defaults:
    CSVFILE=csi_capture.csv  OUTPNG=csi_plot.png
"""
import sys
import re
import numpy as np
import matplotlib
matplotlib.use("Agg")  # headless: write a file, no display needed
import matplotlib.pyplot as plt

CSVFILE = sys.argv[1] if len(sys.argv) > 1 else "csi_capture.csv"
OUTPNG = sys.argv[2] if len(sys.argv) > 2 else "csi_plot.png"

amps = []            # list of per-packet amplitude arrays
local_ts = []        # ESP32 local_timestamp (us), column 18

with open(CSVFILE) as f:
    for line in f:
        if not line.startswith("CSI_DATA"):
            continue
        m = re.search(r"\[(.*)\]", line)
        if not m:
            continue
        raw = [int(x) for x in m.group(1).split() if x not in ("", "-")]
        if len(raw) < 2:
            continue
        # interleaved [imag, real, imag, real, ...] -> amplitude per subcarrier
        a = np.asarray(raw[: (len(raw) // 2) * 2], dtype=np.float64).reshape(-1, 2)
        amp = np.sqrt(a[:, 0] ** 2 + a[:, 1] ** 2)
        amps.append(amp)
        fields = line.split(",")
        try:
            local_ts.append(int(fields[18]))
        except (IndexError, ValueError):
            local_ts.append(np.nan)

if not amps:
    print(f"No CSI_DATA rows found in {CSVFILE}")
    sys.exit(1)

# Pad/truncate to a common subcarrier count so we can stack into a matrix.
ncols = max(len(a) for a in amps)
mat = np.full((len(amps), ncols), np.nan)
for i, a in enumerate(amps):
    mat[i, : len(a)] = a

n_pkts = len(amps)
ts = np.asarray(local_ts, dtype=np.float64)
ts_valid = ts[~np.isnan(ts)]
if len(ts_valid) > 1:
    span_s = (ts_valid[-1] - ts_valid[0]) / 1e6  # local_timestamp is microseconds
    rate = (len(ts_valid) - 1) / span_s if span_s > 0 else float("nan")
    dt_ms = np.diff(ts_valid) / 1e3
else:
    span_s, rate, dt_ms = float("nan"), float("nan"), np.array([])

print(f"packets={n_pkts}  subcarriers={ncols}  span={span_s:.2f}s  mean_rate={rate:.1f} Hz")

fig, axes = plt.subplots(3, 1, figsize=(11, 12))

# 1) Heatmap: subcarrier index (x) vs packet/time (y), color = amplitude
im = axes[0].imshow(mat, aspect="auto", origin="lower", cmap="viridis",
                    interpolation="nearest")
axes[0].set_title(f"CSI amplitude heatmap  ({n_pkts} packets, {ncols} subcarriers)")
axes[0].set_xlabel("Subcarrier index")
axes[0].set_ylabel("Packet # (time ->)")
fig.colorbar(im, ax=axes[0], label="amplitude")

# 2) Mean amplitude per subcarrier (+/- std)
mean_amp = np.nanmean(mat, axis=0)
std_amp = np.nanstd(mat, axis=0)
x = np.arange(ncols)
axes[1].plot(x, mean_amp, color="C0")
axes[1].fill_between(x, mean_amp - std_amp, mean_amp + std_amp, alpha=0.25, color="C0")
axes[1].set_title("Mean CSI amplitude per subcarrier (band = +/-1 std)")
axes[1].set_xlabel("Subcarrier index")
axes[1].set_ylabel("amplitude")

# 3) Inter-packet interval (jitter) -> effective sampling behaviour
if len(dt_ms) > 0:
    axes[2].plot(dt_ms, ".", ms=3, color="C3")
    axes[2].axhline(np.median(dt_ms), color="k", ls="--", lw=1,
                    label=f"median {np.median(dt_ms):.1f} ms  (~{rate:.0f} Hz)")
    axes[2].set_title("Inter-packet interval (sampling jitter)")
    axes[2].set_xlabel("Packet #")
    axes[2].set_ylabel("delta t (ms)")
    axes[2].legend()
else:
    axes[2].text(0.5, 0.5, "not enough timestamps for interval plot",
                 ha="center", va="center")

fig.tight_layout()
fig.savefig(OUTPNG, dpi=120)
print(f"Saved plot -> {OUTPNG}")
