"""Re-draw two report figures from the data MATLAB already saved, without re-running MATLAB.

Why: the original MATLAB figures had two label problems (the E7 axis arrow pointed the wrong
way, and the trade-off legend used the letters A-D instead of the policy names). The MATLAB
scripts are fixed, but re-running them needs a MATLAB licence. Re-simulating in Python or Octave
would change the random numbers and therefore every result, so this script only re-plots the
saved results; every number stays exactly as MATLAB computed it.

Inputs (written by the MATLAB scripts):
  ../drone_battery_ekf/results/run3_stress_tests_E3_E8/stress_runs.mat   (r7B, r7C: experiment E7)
  ../drone_battery_ekf/results/run4_return_home/return_home_results.mat  (SD, SA, died, land: sweep)
  ../drone_battery_ekf/config/ocv_lookup.m                               (OCV table, read as text)
Outputs:
  figures/e7_flat_ocv.png, figures/tradeoff.png

Run from the Report folder:  python replot_figures.py
Needs numpy, scipy and matplotlib.
"""
import re
from pathlib import Path

import numpy as np
import scipy.io as sio
from scipy.interpolate import PchipInterpolator
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
CODE = HERE.parent / "drone_battery_ekf"
RES = CODE / "results"
OUT = HERE / "figures"

# Same colours as the MATLAB scripts (policy order: Voltage, Counting, EKF-mean, EKF-risk)
PCOL = [(0.95, 0.6, 0.1), (0.85, 0.2, 0.2), (0.0, 0.3, 0.9), (0.75, 0.0, 0.75)]
STAGE_B, STAGE_C, SLOPE_COL = (0.0, 0.0, 1.0), (1.0, 0.0, 1.0), (0.85, 0.45, 0.1)

plt.rcParams.update({"font.size": 11, "axes.grid": True, "grid.alpha": 0.3})


def load(path):
    return sio.loadmat(path, squeeze_me=True, struct_as_record=False)


def ocv_table():
    """Read the OCV table straight from config/ocv_lookup.m so the curve always matches the code."""
    text = (CODE / "config" / "ocv_lookup.m").read_text()
    soc = re.search(r"soc_tab\s*=\s*\[([^\]]*)\]\s*/\s*100", text).group(1)
    ocv = re.search(r"ocv_tab\s*=\s*\[([^\]]*)\]", text).group(1)
    return np.array(soc.split(), float) / 100, np.array(ocv.split(), float)


def ocv_slope(s, h=0.005):
    """Same as ocv_lookup.m: pchip curve, slope by a central difference over +/-0.5% SoC."""
    pp = PchipInterpolator(*ocv_table())
    hi, lo = np.minimum(s + h, 1), np.maximum(s - h, 0)
    return (pp(hi) - pp(lo)) / (hi - lo)


def fig_e7():
    m = load(RES / "run3_stress_tests_E3_E8" / "stress_runs.mat")
    fig, ax = plt.subplots(figsize=(8.2, 4.15), dpi=150)
    for key, col, lbl in (("r7B", STAGE_B, "Stage B uncertainty"), ("r7C", STAGE_C, "Stage C uncertainty")):
        r = m[key]
        keep = r.t > 60                                   # skip the first minute (start-up), as in MATLAB
        ax.plot(100 * r.soc[keep], 100 * np.sqrt(r.Pd[0, keep]), color=col, lw=1.6, label=lbl)
    ax.set_ylabel(r"$\sigma_{SoC}$ (% SoC)")
    ax2 = ax.twinx()
    s = np.linspace(0.15, 0.95, 200)
    ax2.plot(100 * s, 1000 * ocv_slope(s) / 100, color=SLOPE_COL, lw=1.2, label="OCV slope")
    ax2.set_ylabel("OCV slope (mV per 1% SoC)", color=SLOPE_COL)
    ax2.tick_params(axis="y", colors=SLOPE_COL)
    ax2.grid(False)
    ax.set_xlim(100, 10)                                  # high SoC on the left: the flight runs left to right
    ax.set_xlabel(r"True SoC (%)   (flight goes this way $\rightarrow$)")
    h1, l1 = ax.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax.legend(h1 + h2, l1 + l2, loc="upper left")
    ax.set_title("E7: where the curve is flat (low slope), stage C becomes less sure", fontsize=11, weight="bold")
    fig.tight_layout()
    fig.savefig(OUT / "e7_flat_ocv.png")
    plt.close(fig)


def summarise(died, land, reserve):
    """Same as summarise() in run4_return_home.m, for one policy."""
    breach = np.mean(died | (land < reserve))
    unused = np.mean(land[~died] - reserve)
    return breach, unused


def fig_tradeoff():
    d = load(RES / "run4_return_home" / "return_home_results.mat")
    reserve = float(d["rp"].reserve)
    n = 200                                               # the sweep used the first 200 Monte Carlo missions
    died, land = d["died"].astype(bool), d["land"]
    sb = summarise(died[:n, 1], land[:n, 1], reserve)     # Counting
    sc = summarise(died[:n, 2], land[:n, 2], reserve)     # EKF-mean
    SA, SD = d["SA"], d["SD"]
    a_thr = [3.40, 3.45, 3.50, 3.55, 3.60]                # as in run4_return_home.m
    d_thr = [0.80, 0.90, 0.95, 0.99, 0.999]

    fig, ax = plt.subplots(figsize=(7.4, 5.1), dpi=150)
    ax.plot(100 * SA.unused, 100 * SA.breach, "o-", color=PCOL[0], mfc=PCOL[0], lw=1.6, label="Voltage (threshold sweep)")
    ax.plot(100 * sb[1], 100 * sb[0], "s", color=PCOL[1], ms=9, label="Counting")
    ax.plot(100 * sc[1], 100 * sc[0], "D", color=PCOL[2], ms=8, label="EKF-mean")
    ax.plot(100 * SD.unused, 100 * SD.breach, "o-", color=PCOL[3], mfc=PCOL[3], lw=1.6, label="EKF-risk (threshold sweep)")
    for k, v in enumerate(a_thr):
        ax.annotate(f"{v:.2f} V", (100 * SA.unused[k], 100 * SA.breach[k]), xytext=(5, 6),
                    textcoords="offset points", color=PCOL[0], fontsize=9)
    for k, v in enumerate(d_thr):
        ax.annotate(f"{100 * v:g}%", (100 * SD.unused[k], 100 * SD.breach[k]), xytext=(5, 6 + 7 * (k % 2)),
                    textcoords="offset points", color=PCOL[3], fontsize=9)
    ax.axvline(0, color="k", lw=0.8, ls=":")
    ax.set_xlim(right=34)                                 # room for the last label
    ax.set_xlabel(r"Unused battery at landing (% SoC)  $\rightarrow$ more wasted range")
    ax.set_ylabel(r"Missions that broke the reserve or died (%)  $\rightarrow$ less safe")
    ax.legend(loc="upper right")
    ax.set_title("Safety vs wasted battery: best is low and just right of zero", fontsize=11, weight="bold")
    fig.tight_layout()
    fig.savefig(OUT / "tradeoff.png")
    plt.close(fig)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    fig_e7()
    fig_tradeoff()
    print("Wrote", OUT / "e7_flat_ocv.png", "and", OUT / "tradeoff.png")
