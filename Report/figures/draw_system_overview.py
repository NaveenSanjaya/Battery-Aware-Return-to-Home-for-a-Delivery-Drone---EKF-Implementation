"""Draw Figure 3.1 (system overview) as fig1_system_overview.png.

Same layout as the original diagram; the EKF block now lists all five states.
Run:  python3 Report/figures/draw_system_overview.py   (needs matplotlib)
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

HERE = Path(__file__).resolve().parent
EDGE, LINE, TEXT, SUB = "#c9c7bd", "#b9b7ad", "#1f1f1f", "#55534d"
BLUE_EDGE, BLUE_FILL = "#2f6fd0", "#e3edf9"
W, H = 2.75, 1.25


def box(ax, x, y, title, lines, highlight=False):
    ax.add_patch(FancyBboxPatch((x, y), W, H, boxstyle="round,pad=0,rounding_size=0.12",
                                fc=BLUE_FILL if highlight else "white",
                                ec=BLUE_EDGE if highlight else EDGE, lw=2.2 if highlight else 1.6))
    ax.text(x + W / 2, y + H - 0.32, title, ha="center", va="center", fontsize=13, weight="bold", color=TEXT)
    for i, s in enumerate(lines):
        ax.text(x + W / 2, y + H - 0.62 - 0.28 * i, s, ha="center", va="center", fontsize=11.5, color=SUB)


def arrow(ax, pts, label=None, label_at=None):
    xs, ys = zip(*pts)
    ax.plot(xs[:-1] + (xs[-1],), ys[:-1] + (ys[-1],), color=LINE, lw=1.6, solid_capstyle="butt")
    ax.annotate("", xy=pts[-1], xytext=pts[-2],
                arrowprops=dict(arrowstyle="-|>", color=LINE, lw=1.6, mutation_scale=14, shrinkA=0, shrinkB=0))
    if label:
        ax.text(*label_at, label, ha="center", va="center", fontsize=11.5, color=SUB)


fig, ax = plt.subplots(figsize=(13.3, 5.8))
ax.set_xlim(0, 13.3)
ax.set_ylim(0, 5.8)
ax.axis("off")

ax.text(0.35, 5.35, "Noisy sensors feed the EKF; its uncertainty drives the go-home call",
        fontsize=15, weight="bold", color=TEXT, va="center")

x1, x2, x3, x4 = 0.35, 3.68, 7.0, 10.33
yt, yb = 3.2, 1.1
box(ax, x1, yt, "Simulator", ["true flight path", "true 2-RC battery"])
box(ax, x2, yt, "Sensors", ["current (biased)", "voltage (noisy)"])
box(ax, x3, yt, "EKF", [r"SoC, V$_1$, b, C$_n$, R$_0$", "+ uncertainty P"], highlight=True)
box(ax, x4, yt, "Decision rule", ["P(safe return)", "below 95%: go home"])
box(ax, x1, yb, "Scoring", ["failures, unused", "battery, SoC error"])
box(ax, x3, yb, "Baselines", ["charge counting", "voltage threshold"])

ym = yt + H / 2
arrow(ax, [(x1 + W, ym), (x2, ym)])
arrow(ax, [(x2 + W, ym), (x3, ym)])
arrow(ax, [(x3 + W, ym), (x4, ym)])
arrow(ax, [(x1 + W / 2, yt), (x1 + W / 2, yb + H)], "truth", (x1 + W / 2 + 0.38, (yt + yb + H) / 2))
yl = yb + H / 2
arrow(ax, [(x2 + W / 2, yt), (x2 + W / 2, yl), (x3, yl)])
arrow(ax, [(x3 + W, yl), (x4 + 0.62, yl), (x4 + 0.62, yt)])
arrow(ax, [(x4 + W - 0.62, yt), (x4 + W - 0.62, 0.45), (x1 + W / 2, 0.45), (x1 + W / 2, yb)],
      "turn-back moment of each policy", (6.6, 0.65))

fig.savefig(HERE / "fig1_system_overview.png", dpi=110, bbox_inches="tight", facecolor="white")
print("Saved", HERE / "fig1_system_overview.png")
