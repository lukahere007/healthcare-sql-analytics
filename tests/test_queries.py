"""Every question file runs on the real extract and passes generic sanity checks."""

import pandas as pd
import pytest

from ehr_sql import list_questions, run_query

QUESTIONS = list_questions()


def test_there_are_ten_questions():
    assert len(QUESTIONS) == 10


@pytest.mark.parametrize("q", QUESTIONS, ids=lambda q: q.name)
def test_question_header_is_complete(q):
    assert "title" in q.meta and q.grain, f"{q.name}: add '-- title:' and '-- grain:' header lines"


@pytest.mark.parametrize("q", QUESTIONS, ids=lambda q: q.name)
def test_question_runs_and_is_sane(con, q):
    df = run_query(con, q)
    assert not df.empty, "query returned no rows"
    missing = [c for c in q.grain + q.rate_columns if c not in df.columns]
    assert not missing, f"header names columns not in the result: {missing}"
    assert not df.duplicated(subset=q.grain).any(), f"duplicate rows for grain {q.grain}"
    for col in q.rate_columns:
        vals = pd.to_numeric(df[col]).dropna()
        assert ((vals >= 0) & (vals <= 1)).all(), f"{col} outside [0, 1]"


def _result(con, name):
    return run_query(con, next(q for q in QUESTIONS if q.name == name))


def test_demographics_total_matches_living_patients(con):
    df = _result(con, "01_demographics")
    total = df[(df.age_band == "All ages") & (df.gender == "All")].patients.item()
    living = con.execute("SELECT COUNT(*) FROM int_patients WHERE alive_at_as_of").fetchone()[0]
    assert total == living
    detail = df[(df.age_band != "All ages") & (df.gender != "All")]
    assert detail.patients.sum() == living


def test_readmission_overall_row_is_consistent(con):
    df = _result(con, "03_readmission_30d")
    overall = df[df.principal_reason == "ALL INDEX STAYS"].iloc[0]
    by_reason = df[df.principal_reason != "ALL INDEX STAYS"]
    assert by_reason.index_stays.sum() == overall.index_stays
    assert by_reason.readmissions_all_cause.sum() == overall.readmissions_all_cause
    assert overall.readmissions_unplanned <= overall.readmissions_all_cause
    assert overall.all_cause_readmission_rate == pytest.approx(
        overall.readmissions_all_cause / overall.index_stays, abs=1e-4)


def test_cost_drivers_cumulative_share_increases(con):
    df = _result(con, "05_cost_drivers")
    assert df.cumulative_share.is_monotonic_increasing
    assert len(df) == 15


def test_hypertension_cohort_shares_sum_to_one(con):
    df = _result(con, "08_hypertension_first_line")
    assert df.share_of_cohort.sum() == pytest.approx(1.0, abs=1e-3)


def test_monthly_spine_has_no_gaps(con):
    df = _result(con, "09_monthly_encounter_trends")
    months = pd.to_datetime(df.month)
    assert (months.diff().dropna().dt.days.between(28, 31)).all()
    assert (df.total >= df.drop(columns=["month", "total", "mom_change", "yoy_pct_change",
                                         "rolling_12m_avg", "ytd_total"]).sum(axis=1)).all()


def test_kaplan_meier_is_monotone(con):
    df = _result(con, "10_prediabetes_to_diabetes_km")
    assert df.cumulative_incidence.is_monotonic_increasing
    assert df.n_still_at_risk.is_monotonic_decreasing
    assert df.cumulative_incidence.iloc[0] == 0
