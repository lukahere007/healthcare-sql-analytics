"""Data-quality checks in sql/checks/ run as tests.

severity: error -> must return no rows; severity: warn -> reported, must run.
"""

import pytest

from ehr_sql import list_checks, run_query

CHECKS = list_checks()


@pytest.mark.parametrize("check", [c for c in CHECKS if c.meta.get("severity") == "error"],
                         ids=lambda c: c.name)
def test_error_checks_pass(con, check):
    failures = run_query(con, check)
    assert failures.empty, "\n" + failures.to_string(index=False)


@pytest.mark.parametrize("check", [c for c in CHECKS if c.meta.get("severity") != "error"],
                         ids=lambda c: c.name)
def test_warn_and_info_checks_run(con, check):
    run_query(con, check)


def test_profile_covers_every_staged_table(con):
    profile = run_query(con, next(c for c in CHECKS if c.name == "dq_00_profile"))
    assert set(profile.table_name) == {"stg_patients", "stg_encounters", "stg_conditions",
                                       "stg_medications", "stg_observations"}
    assert profile.null_rate.between(0, 1).all()


def test_checks_catch_a_planted_orphan(fixture_con):
    """The orphan-key check must actually detect a broken reference."""
    fixture_con.execute(
        "INSERT INTO raw_encounters (Id, START, STOP, PATIENT, PAYER, ENCOUNTERCLASS) "
        "VALUES ('X', '2020-01-01T00:00:00Z', '2020-01-01T01:00:00Z', 'NOBODY', 'P1', 'ambulatory')"
    )
    check = next(c for c in CHECKS if c.name == "dq_02_orphan_keys")
    rules = set(run_query(fixture_con, check).rule)
    assert "encounters.patient_id -> patients" in rules
