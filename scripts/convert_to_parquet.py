"""Convert the Synthea CSV export into compact Parquet files for the repo.

Columns are kept as text (``all_varchar``) on purpose: typing, casting and
cleaning happen in SQL (``sql/01_staging.sql``), which is part of what this
project demonstrates.

Rules applied here (also written to data/raw/MANIFEST.json):
* only the tables the analysis uses are kept;
* ``observations`` is restricted to the LOINC codes in OBSERVATION_CODES
  (the full table is ~2M rows / 380 MB of CSV, mostly survey answers);
* rows are sorted so that the files are deterministic for a given Synthea run.

Usage: python scripts/convert_to_parquet.py <csv_dir> <out_dir> [--command ...]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import duckdb

# Columns dropped on export. They are synthetic, but the analysis does not need
# direct identifiers, so we follow the "minimum necessary" habit anyway.
DROP_COLUMNS = {
    "patients": ["SSN", "DRIVERS", "PASSPORT", "PREFIX", "FIRST", "MIDDLE", "LAST",
                 "SUFFIX", "MAIDEN", "ADDRESS", "LAT", "LON"],
}

TABLES = {
    # table: ORDER BY columns (for deterministic output)
    "patients": "Id",
    "encounters": "PATIENT, START, Id",
    "conditions": "PATIENT, START, CODE, ENCOUNTER",
    "medications": "PATIENT, START, CODE, ENCOUNTER",
    "observations": "PATIENT, DATE, CODE, ENCOUNTER, VALUE",
    "organizations": "Id",
    "payers": "Id",
}

OBSERVATION_CODES = {
    "4548-4": "Hemoglobin A1c/Hemoglobin.total in Blood",
    "8480-6": "Systolic Blood Pressure",
    "8462-4": "Diastolic Blood Pressure",
    "39156-5": "Body mass index (BMI)",
    "2093-3": "Cholesterol [Mass/volume] in Serum or Plasma",
    "18262-6": "Cholesterol in LDL [Mass/volume] in Serum or Plasma (direct)",
    "33914-3": "eGFR (MDRD)",
    "72166-2": "Tobacco smoking status",
}


def convert(csv_dir: Path, out_dir: Path) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    counts = {}
    for table, order_by in TABLES.items():
        src = (csv_dir / f"{table}.csv").as_posix()
        dst = (out_dir / f"{table}.parquet").as_posix()
        where = ""
        if table == "observations":
            codes = ", ".join(f"'{c}'" for c in OBSERVATION_CODES)
            where = f"WHERE CODE IN ({codes})"
        exclude = DROP_COLUMNS.get(table)
        select = f"* EXCLUDE ({', '.join(exclude)})" if exclude else "*"
        query = (
            f"SELECT {select} FROM read_csv('{src}', header=true, all_varchar=true) "
            f"{where} ORDER BY {order_by}"
        )
        con.execute(f"COPY ({query}) TO '{dst}' (FORMAT parquet, COMPRESSION zstd)")
        counts[table] = con.execute(f"SELECT count(*) FROM '{dst}'").fetchone()[0]
        print(f"{table:14s} {counts[table]:>9,d} rows -> {dst}")
    return counts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_dir", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--command", default="")
    ap.add_argument("--synthea-version", default="")
    args = ap.parse_args()

    counts = convert(args.csv_dir, args.out_dir)
    manifest = {
        "source": "Synthea synthetic patient generator (https://github.com/synthetichealth/synthea)",
        "synthea_version": args.synthea_version,
        "command": args.command,
        "tables": counts,
        "observation_codes_kept": OBSERVATION_CODES,
        "dropped_columns": DROP_COLUMNS,
        "notes": "All columns stored as text; typed in sql/01_staging.sql.",
    }
    (args.out_dir / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
