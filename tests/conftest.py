from pathlib import Path

import duckdb
import pandas as pd
import pytest

from ehr_sql import REPO_ROOT, build_database
from ehr_sql.db import SQL_DIR, build_layers

FIXTURES = Path(__file__).parent / "fixtures"

# Column lists of the raw Synthea tables the staging layer reads, so a fixture
# database can be built from a handful of hand-written rows.
RAW_COLUMNS = {
    "patients": ["Id", "BIRTHDATE", "DEATHDATE", "GENDER", "RACE", "ETHNICITY", "MARITAL", "COUNTY", "INCOME"],
    "encounters": ["Id", "START", "STOP", "PATIENT", "ORGANIZATION", "PAYER", "ENCOUNTERCLASS", "CODE",
                   "DESCRIPTION", "BASE_ENCOUNTER_COST", "TOTAL_CLAIM_COST", "PAYER_COVERAGE",
                   "REASONCODE", "REASONDESCRIPTION"],
    "conditions": ["START", "STOP", "PATIENT", "ENCOUNTER", "SYSTEM", "CODE", "DESCRIPTION"],
    "medications": ["START", "STOP", "PATIENT", "PAYER", "ENCOUNTER", "CODE", "DESCRIPTION", "BASE_COST",
                    "PAYER_COVERAGE", "DISPENSES", "TOTALCOST", "REASONCODE", "REASONDESCRIPTION"],
    "observations": ["DATE", "PATIENT", "ENCOUNTER", "CATEGORY", "CODE", "DESCRIPTION", "VALUE", "UNITS", "TYPE"],
    "organizations": ["Id", "NAME"],
    "payers": ["Id", "NAME", "OWNERSHIP"],
}


@pytest.fixture(scope="session")
def con():
    """Database built from the committed Synthea extract."""
    if not (REPO_ROOT / "data" / "raw" / "patients.parquet").exists():
        pytest.skip("data/raw not present - run scripts/generate_synthea.sh")
    c = build_database()
    yield c
    c.close()


@pytest.fixture()
def fixture_con():
    """Database built from tests/fixtures/*.csv (tiny, hand-made, known answers)."""
    c = duckdb.connect()
    for table, cols in RAW_COLUMNS.items():
        path = FIXTURES / f"{table}.csv"
        if path.exists():
            df = pd.read_csv(path, dtype=str, keep_default_na=False).replace({"": None})
        else:
            df = pd.DataFrame({col: pd.Series(dtype=str) for col in cols})
        c.register(f"_{table}", df)
        c.execute(f"CREATE TABLE raw_{table} AS SELECT * FROM _{table}")
    load_sql = (SQL_DIR / "00_load.sql").read_text()
    ref_sql = load_sql[load_sql.index("CREATE OR REPLACE TABLE ref_"):]
    c.execute(ref_sql.replace("'data/", f"'{(REPO_ROOT / 'data').as_posix()}/"))
    build_layers(c)
    yield c
    c.close()
