"""SQL analytics on synthetic EHR data (Synthea) with DuckDB."""

from .db import (
    REPO_ROOT,
    Query,
    build_database,
    list_checks,
    list_questions,
    run_query,
    run_sql_script,
)

__all__ = [
    "REPO_ROOT",
    "Query",
    "build_database",
    "list_checks",
    "list_questions",
    "run_query",
    "run_sql_script",
]
