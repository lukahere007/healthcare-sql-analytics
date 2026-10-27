"""Build the DuckDB database and run the .sql files in sql/.

All analysis logic lives in SQL. This module only wires files together:

* ``sql/00_load.sql``          raw tables from data/raw/*.parquet
* ``sql/01_staging.sql``       typed views (stg_*), parameters and macros
* ``sql/02_intermediate.sql``  shared definitions (int_*)
* ``sql/questions/*.sql``      one business/clinical question per file
* ``sql/checks/*.sql``         data-quality checks (each returns violating rows)

Each question/check file starts with a header of ``-- key: value`` lines that
the runner and the tests read, e.g. ``-- title:``, ``-- grain:`` (columns that
must be unique in the result) and ``-- rate_columns:`` (must lie in [0, 1]).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import duckdb
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = REPO_ROOT / "sql"
DATA_DIR = REPO_ROOT / "data"

BUILD_SCRIPTS = ["01_staging.sql", "02_intermediate.sql"]


@dataclass
class Query:
    path: Path
    sql: str
    meta: dict[str, str] = field(default_factory=dict)

    @property
    def name(self) -> str:
        return self.path.stem

    @property
    def title(self) -> str:
        return self.meta.get("title", self.name)

    def _list(self, key: str) -> list[str]:
        raw = self.meta.get(key, "")
        return [c.strip() for c in raw.split(",") if c.strip()]

    @property
    def grain(self) -> list[str]:
        return self._list("grain")

    @property
    def rate_columns(self) -> list[str]:
        return self._list("rate_columns")


_META_RE = re.compile(r"^--\s*([a-z_]+):\s*(.+?)\s*$")


def load_query(path: Path) -> Query:
    sql = path.read_text()
    meta: dict[str, str] = {}
    for line in sql.splitlines():
        if not line.startswith("--"):
            break
        m = _META_RE.match(line)
        if m:
            meta[m.group(1)] = m.group(2)
    return Query(path=path, sql=sql, meta=meta)


def list_questions() -> list[Query]:
    return [load_query(p) for p in sorted((SQL_DIR / "questions").glob("*.sql"))]


def list_checks() -> list[Query]:
    return [load_query(p) for p in sorted((SQL_DIR / "checks").glob("*.sql"))]


def run_sql_script(con: duckdb.DuckDBPyConnection, path: Path, data_dir: Path | None = None) -> None:
    """Execute every statement in a .sql file (used for the build scripts)."""
    sql = path.read_text()
    if data_dir is not None:
        # 00_load.sql uses repo-relative paths so it also works from the CLI
        sql = sql.replace("'data/", f"'{data_dir.as_posix()}/")
    con.execute(sql)


def run_query(con: duckdb.DuckDBPyConnection, query: Query | Path) -> pd.DataFrame:
    """Run a single-statement question/check file and return the result."""
    if isinstance(query, Path):
        query = load_query(query)
    return con.execute(query.sql).df()


def build_layers(con: duckdb.DuckDBPyConnection) -> None:
    """Create params, staging and intermediate views on top of raw_* tables."""
    for script in BUILD_SCRIPTS:
        run_sql_script(con, SQL_DIR / script)


def build_database(db_path: str | Path = ":memory:", data_dir: Path = DATA_DIR) -> duckdb.DuckDBPyConnection:
    """Load the raw extract and build every analytical layer."""
    con = duckdb.connect(str(db_path))
    run_sql_script(con, SQL_DIR / "00_load.sql", data_dir=data_dir)
    build_layers(con)
    return con
