"""Figures for the README, drawn from the query results (results/*.csv)."""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
SURFACE, INK, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"

plt.rcParams.update({
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "axes.edgecolor": MUTED,
    "axes.labelcolor": INK,
    "axes.titlesize": 12,
    "axes.titleweight": "bold",
    "axes.titlelocation": "left",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "font.size": 10,
    "legend.frameon": False,
})

SYNTHETIC_NOTE = "Synthea synthetic data - describes the simulator, not real-world epidemiology"


def _footer(fig) -> None:
    fig.text(0.01, 0.01, SYNTHETIC_NOTE, fontsize=8, color=MUTED, ha="left", va="bottom")


def _short(label: str, width: int = 48) -> str:
    label = label.replace("  ", " ")
    return label if len(label) <= width else label[: width - 1] + "…"


def readmission_by_reason(df: pd.DataFrame, out: Path) -> None:
    overall = df[df["principal_reason"] == "ALL INDEX STAYS"].iloc[0]
    d = df[df["principal_reason"] != "ALL INDEX STAYS"].sort_values("all_cause_readmission_rate")
    y = np.arange(len(d))
    h = 0.38
    fig, ax = plt.subplots(figsize=(9, 5.6))
    ax.barh(y + h / 2, d["all_cause_readmission_rate"] * 100, height=h, color=BLUE, label="All-cause")
    ax.barh(y - h / 2, d["unplanned_readmission_rate"] * 100, height=h, color=ORANGE, label="Unplanned only")
    ax.set_yticks(y, [f"{_short(r)} (n={n})" for r, n in zip(d["principal_reason"], d["index_stays"])])
    ax.axvline(overall["all_cause_readmission_rate"] * 100, color=MUTED, lw=1, ls="--")
    ax.text(overall["all_cause_readmission_rate"] * 100 + 0.4, len(d) - 0.6,
            f"overall all-cause {overall['all_cause_readmission_rate']:.1%}", color=MUTED, fontsize=8)
    ax.set_xlabel("30-day readmission rate (%)")
    ax.grid(axis="y", visible=False)
    fig.suptitle("30-day readmission rate by principal reason of the index stay",
                 x=0.01, ha="left", fontweight="bold", fontsize=12)
    ax.legend(loc="lower right")
    _footer(fig)
    fig.tight_layout(rect=(0, 0.03, 1, 0.97))
    fig.savefig(out, dpi=150)
    plt.close(fig)


def prevalence_heatmap(df: pd.DataFrame, out: Path) -> None:
    cols = ["prev_0_17", "prev_18_39", "prev_40_64", "prev_65_74", "prev_75_84", "prev_85_plus"]
    labels = ["0-17", "18-39", "40-64", "65-74", "75-84", "85+"]
    d = df.set_index("condition_group")[cols]
    fig, ax = plt.subplots(figsize=(8, 5.6))
    im = ax.imshow(d.values * 100, cmap="Blues", vmin=0, vmax=100, aspect="auto")
    ax.set_xticks(range(len(labels)), labels)
    ax.set_yticks(range(len(d)), d.index)
    ax.grid(False)
    for (i, j), v in np.ndenumerate(d.values * 100):
        ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=8,
                color="white" if v > 55 else INK)
    ax.set_xlabel("Age band on the as-of date")
    ax.set_title("Active chronic conditions, % of living patients in each age band")
    cb = fig.colorbar(im, ax=ax, shrink=0.8)
    cb.set_label("% of age band")
    _footer(fig)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(out, dpi=150)
    plt.close(fig)


def monthly_trend(df: pd.DataFrame, out: Path) -> None:
    d = df.copy()
    d["month"] = pd.to_datetime(d["month"])
    fig, ax = plt.subplots(figsize=(9, 4.2))
    ax.plot(d["month"], d["total"], color=BLUE, lw=1.2, alpha=0.45, label="Monthly encounters")
    ax.plot(d["month"], d["rolling_12m_avg"], color=BLUE, lw=2, label="12-month moving average")
    ax.plot(d["month"], d["outpatient"], color=ORANGE, lw=1.5, label="Outpatient")
    ax.set_ylabel("Encounters per month")
    ax.set_ylim(0, None)
    ax.set_title("Monthly encounter volume")
    ax.legend(loc="upper left", ncols=3)
    _footer(fig)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(out, dpi=150)
    plt.close(fig)


def km_curve(df: pd.DataFrame, out: Path) -> None:
    fig, ax = plt.subplots(figsize=(8, 4.2))
    ax.plot(df["years_since_prediabetes"], df["cumulative_incidence"] * 100, color=BLUE, lw=2,
            marker="o", ms=3)
    for yr in (5, 10, 20):
        v = df.loc[df["years_since_prediabetes"] == yr, "cumulative_incidence"].iloc[0] * 100
        ax.plot([yr], [v], "o", color=BLUE, ms=6, mec=SURFACE, mew=2)
        ax.annotate(f"{yr} y: {v:.1f}%", (yr, v), xytext=(6, -12), textcoords="offset points",
                    color=INK, fontsize=9)
    ax.set_xlabel("Years since prediabetes diagnosis (KM estimate read at whole-year landmarks)")
    ax.set_ylabel("Progressed to type 2 diabetes (%)")
    ax.set_ylim(0, None)
    ax.set_title(f"Kaplan-Meier cumulative incidence, prediabetes -> type 2 diabetes "
                 f"(n={int(df['cohort_size'].iloc[0])})")
    _footer(fig)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(out, dpi=150)
    plt.close(fig)


def make_figures(results: dict[str, pd.DataFrame], fig_dir: Path) -> list[Path]:
    fig_dir.mkdir(parents=True, exist_ok=True)
    plan = [
        ("03_readmission_30d", readmission_by_reason, "readmission_by_reason.png"),
        ("02_chronic_prevalence_by_age", prevalence_heatmap, "chronic_prevalence_heatmap.png"),
        ("09_monthly_encounter_trends", monthly_trend, "monthly_encounters.png"),
        ("10_prediabetes_to_diabetes_km", km_curve, "prediabetes_km.png"),
    ]
    paths = []
    for name, fn, fname in plan:
        path = fig_dir / fname
        fn(results[name], path)
        paths.append(path)
    return paths
