"""Re-draw two report figures from the saved MATLAB results, without MATLAB.

The data comes straight from the .mat files written by the MATLAB scripts, so every
number is unchanged; only labels are corrected:
  * stress_e7_flat_ocv.png : E7 (run3), with the flight-direction arrow pointing the right way
  * rth_tradeoff.png       : threshold sweep (run4), with the policy names used in the report

Run from anywhere:  python3 Report/figures/replot_from_results.py
Needs numpy, scipy and matplotlib.
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
from scipy.interpolate import PchipInterpolator

HERE = Path(__file__).resolve().parent
RESULTS = HERE.parent.parent / "drone_battery_ekf" / "results"

# Same colours as the MATLAB figures
ORANGE, RED, BLUE, MAGENTA = (0.95, 0.6, 0.1), (0.85, 0.2, 0.2), (0, 0.3, 0.9), (0.75, 0, 0.75)
plt.rcParams.update({"font.size": 11, "axes.grid": True, "grid.alpha": 0.3})


def load(path):
    return sio.loadmat(path, squeeze_me=True, struct_as_record=False)


# ---------------------------------------------------------------- E7: uncertainty vs flat OCV
def ocv_slope_mv_per_pct(s):
    """Same OCV table, pchip fit and +/-0.5% central difference as config/ocv_lookup.m."""
    soc_tab = np.array([0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]) / 100
    ocv_tab = np.array([3.30, 3.45, 3.55, 3.63, 3.68, 3.73, 3.78, 3.85, 3.93, 4.00, 4.08, 4.18])
    pp = PchipInterpolator(soc_tab, ocv_tab)
    hi, lo = np.minimum(s + 0.005, 1), np.maximum(s - 0.005, 0)
    slope = (pp(hi) - pp(lo)) / (hi - lo)          # V per unit SoC
    return 1000 * slope / 100                        # mV per 1% SoC


def plot_e7():
    m = load(RESULTS / "run3_stress_tests_E3_E8" / "stress_runs.mat")
    rB, rC = m["r7B"], m["r7C"]
    fig, ax = plt.subplots(figsize=(9, 4.2))
    for r, col, lbl in [(rB, "b", "Stage B uncertainty"), (rC, MAGENTA, "Stage C uncertainty")]:
        keep = r.t > 60                               # skip the first minute (start-up)
        ax.plot(100 * r.soc[keep], 100 * np.sqrt(r.Pd[0, keep]), color=col, lw=1.6, label=lbl)
    ax.set_ylabel(r"$\sigma_{SoC}$ (% SoC)")
    ax2 = ax.twinx()
    s = np.linspace(0.15, 0.95, 200)
    ax2.plot(100 * s, ocv_slope_mv_per_pct(s), color=(0.85, 0.45, 0.1), lw=1.2, label="OCV slope")
    ax2.set_ylabel("OCV slope (mV per 1% SoC)", color=(0.85, 0.45, 0.1))
    ax2.grid(False)
    ax.set_xlim(100, 10)                              # flight starts full (left) and ends low (right)
    ax.set_xlabel(r"True SoC (%)   (flight goes this way $\rightarrow$)")
    ax.set_title("E7: where the curve is flat (low slope), stage C becomes less sure")
    lines = ax.get_lines() + ax2.get_lines()
    ax.legend(lines, [l.get_label() for l in lines], loc="upper left")
    fig.tight_layout()
    fig.savefig(HERE / "stress_e7_flat_ocv.png", dpi=150)
    plt.close(fig)


# ---------------------------------------------------------------- threshold sweep trade-off
def summarise(died, land, reserve):
    """Same as summarise() in run4_return_home.m: breach rate and unused battery (landed only)."""
    breach = np.mean(died | (land < reserve))
    unused = np.mean(land[~died] - reserve)
    return 100 * breach, 100 * unused


def plot_tradeoff():
    d = load(RESULTS / "run4_return_home" / "return_home_results.mat")
    reserve = float(d["rp"].reserve)
    SA, SD = d["SA"], d["SD"]
    died, land = d["died"].astype(bool), d["land"]
    n = 200                                           # the sweep used the first 200 missions
    bB, uB = summarise(died[:n, 1], land[:n, 1], reserve)
    bC, uC = summarise(died[:n, 2], land[:n, 2], reserve)
    A_thr = [3.40, 3.45, 3.50, 3.55, 3.60]
    D_thr = [0.80, 0.90, 0.95, 0.99, 0.999]

    fig, ax = plt.subplots(figsize=(8, 5.5))
    ax.plot(100 * SA.unused, 100 * SA.breach, "o-", color=ORANGE, lw=1.6, label="Voltage (threshold sweep)")
    ax.plot(uB, bB, "s", color=RED, ms=9, label="Counting")
    ax.plot(uC, bC, "D", color=BLUE, ms=8, label="EKF-mean")
    ax.plot(100 * SD.unused, 100 * SD.breach, "o-", color=MAGENTA, lw=1.6, label="EKF-risk (threshold sweep)")
    for x, y, t in zip(100 * SA.unused, 100 * SA.breach, A_thr):
        ax.annotate(f"{t:.2f} V", (x, y), xytext=(5, 6), textcoords="offset points", color=ORANGE, fontsize=9)
    for x, y, t in zip(100 * SD.unused, 100 * SD.breach, D_thr):
        ax.annotate(f"{100 * t:g}%", (x, y), xytext=(0, -15), textcoords="offset points", color=MAGENTA, fontsize=9, ha="center")
    ax.axvline(0, color="k", lw=0.8, ls=":")
    ax.set_xlabel("Unused battery at landing (% SoC above the reserve)")
    ax.set_ylabel("Missions that broke the reserve or died (%)")
    ax.set_title("Safety vs wasted battery (200 missions)")
    ax.legend(loc="upper right")
    fig.tight_layout()
    fig.savefig(HERE / "rth_tradeoff.png", dpi=150)
    plt.close(fig)


if __name__ == "__main__":
    plot_e7()
    plot_tradeoff()
    print("Saved stress_e7_flat_ocv.png and rth_tradeoff.png in", HERE)
