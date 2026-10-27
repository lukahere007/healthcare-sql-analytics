"""Hand-built fixtures with answers worked out on paper.

Readmission fixture (as-of 2025-06-30, study window from 2015-07-01):

Patient A (adult, alive) - 5 inpatient encounters -> 4 stays
  stay 1  A1 01-01..01-05 + A2 01-05..01-08 overlap -> one stay (transfer, NOT a readmission)
  stay 2  A3 01-20..01-23  12 days after stay 1     -> stay 1 readmitted (unplanned: pneumonia)
  stay 3  A4 02-23..02-25  31 days after stay 2     -> stay 2 NOT readmitted (boundary)
  stay 4  A5 03-10..03-12  14 days after stay 3     -> stay 3 readmitted, but PLANNED (transplant)
  stay 4 has no later stay                           -> not readmitted
Patient B (adult, dies 2020-03-15)
  B1 02-01..02-10, B2 03-11..03-15 (exactly 30 days)  -> B1 readmitted (unplanned: sepsis)
  B2 ends in death                                   -> excluded as an index stay
Patient C (child)  -> both stays excluded (age < 18)
Patient D          -> D0 discharged before the study window, D1 within 30 days of as-of: excluded

Index stays = A:4 + B:1 = 5; all-cause readmissions = 3 (A1, A3, B1) -> 0.6;
unplanned = 2 (A1, B1) -> 0.4.
"""

from ehr_sql import list_questions, run_query


def _question(name):
    return next(q for q in list_questions() if q.name == name)


def test_transfers_are_merged_into_one_stay(fixture_con):
    stays = fixture_con.execute(
        "SELECT patient_id, COUNT(*) AS n FROM int_inpatient_stays GROUP BY 1 ORDER BY 1"
    ).fetchall()
    assert stays == [("A", 4), ("B", 2), ("C", 2), ("D", 2)]
    first = fixture_con.execute(
        "SELECT n_encounters, los_days, stay_cost FROM int_inpatient_stays WHERE stay_id = 'A:1'"
    ).fetchone()
    assert first[0] == 2 and first[1] == 7 and float(first[2]) == 3000.0


def test_readmission_rate_matches_hand_calculation(fixture_con):
    df = run_query(fixture_con, _question("03_readmission_30d"))
    overall = df[df["principal_reason"] == "ALL INDEX STAYS"].iloc[0]
    assert overall["index_stays"] == 5
    assert overall["patients"] == 2
    assert overall["readmissions_all_cause"] == 3
    assert overall["readmissions_unplanned"] == 2
    assert overall["all_cause_readmission_rate"] == 0.6
    assert overall["unplanned_readmission_rate"] == 0.4


def test_medication_episodes_gaps_and_islands(fixture_con):
    eps = fixture_con.execute(
        """SELECT rxnorm_code, episode_seq, CAST(episode_start_ts AS DATE)::VARCHAR,
                  CAST(episode_end_ts AS DATE)::VARCHAR, n_prescriptions
           FROM int_medication_episodes ORDER BY rxnorm_code, episode_seq"""
    ).fetchall()
    assert eps == [
        # 10-day gap is bridged by the 30-day grace period; 61-day gap is not
        ("111", 1, "2020-01-01", "2020-03-01", 2),
        ("111", 2, "2020-05-01", "2020-06-01", 1),
        # a record nested inside a longer one is absorbed (running MAX of stop)
        ("222", 1, "2020-01-10", "2020-02-15", 2),
        # code 333 stops before it starts -> dropped
    ]
