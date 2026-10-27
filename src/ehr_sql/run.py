"""Run the whole pipeline: build DB -> data-quality checks -> questions -> results/ + figures/.

    python -m ehr_sql.run                 # in-memory database
    python -m ehr_sql.run --db ehr.duckdb # keep the database to explore with the DuckDB CLI
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import pandas as pd

from .db import REPO_ROOT, build_database, list_checks, list_questions, run_query
from .figures import make_figures


def run_checks(con) -> pd.DataFrame:
    rows = []
    for check in list_checks():
        if check.meta.get("severity") == "info":
            continue
        res = run_query(con, check)
        severity = check.meta.get("severity", "error")
        if res.empty:
            rows.append({"check": check.name, "severity": severity, "rule": "(all rules)",
                         "failing_rows": 0, "status": "pass"})
        for r in res.itertuples(index=False):
            rows.append({"check": check.name, "severity": severity, "rule": r.rule,
                         "failing_rows": int(r.failing_rows),
                         "status": "FAIL" if severity == "error" else "warn"})
    return pd.DataFrame(rows)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=":memory:", help="DuckDB file to create (default: in memory)")
    ap.add_argument("--results", type=Path, default=REPO_ROOT / "results")
    ap.add_argument("--figures", type=Path, default=REPO_ROOT / "figures")
    args = ap.parse_args(argv)

    t0 = time.perf_counter()
    con = build_database(args.db)
    args.results.mkdir(parents=True, exist_ok=True)

    dq = run_checks(con)
    dq.to_csv(args.results / "data_quality.csv", index=False)
    profile = next(c for c in list_checks() if c.meta.get("severity") == "info")
    run_query(con, profile).to_csv(args.results / "data_profile.csv", index=False)
    print(dq.to_string(index=False))
    if (dq["status"] == "FAIL").any():
        print("\nData-quality checks FAILED - not running the questions.", file=sys.stderr)
        return 1

    results = {}
    for q in list_questions():
        df = run_query(con, q)
        df.to_csv(args.results / f"{q.name}.csv", index=False)
        results[q.name] = df
        print(f"\n== {q.name}: {q.title} ({len(df)} rows)")
        print(df.head(6).to_string(index=False))

    for p in make_figures(results, args.figures):
        print(f"figure -> {p.relative_to(REPO_ROOT)}")
    print(f"\nDone in {time.perf_counter() - t0:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
