---
date: 2026-09-21
phase: pipelines
topic: Trigger combinations and complex firing patterns
---

# Trigger combinations and complex firing patterns

*Pipelines and orchestration*

## Concept

Trigger combinations define *when* a pipeline step executes—firing based on upstream task states, data freshness, or conditional logic. Complex firing patterns emerge when you need steps to run only under specific combinations: "run job_b if job_a succeeded AND data arrived within 4 hours" or "skip enrichment if row count dropped >50%." Without explicit trigger rules, pipelines either run too much (wasting resources, obscuring real failures) or too little (leaving stale data undetected). Modern orchestrators (Airflow, dbt Cloud, Dagster) separate trigger logic from task logic, making dependencies visible and testable—critical for auditing why a report is stale or why a backfill re-ran unexpectedly.

Trigger patterns also encode *recovery behavior*. A step can fire on "upstream_failed" to alert, quarantine bad data, or auto-rollback. A step can fire on "skipped" to propagate that skip downstream (preventing orphaned results). Poorly designed triggers lead to cascading failures (one skipped job breaks ten dependents) or silent data rot (a job marked "complete" but actually empty). Loud failure—making triggers explicit and monitoring their outcomes—means you catch these gaps before they reach dashboards.

## Practice

**Problem:** Job postings arrive daily by 06:00 UTC. The `job_postings_fact` table must refresh by 08:00 UTC. However, if fewer than 100 new postings arrived overnight, we suspect a data collection failure and should alert instead of loading stale data. If the collection succeeds but the transform job fails twice, we should fall back to the previous day's snapshot and mark the current load as "degraded."

```sql
-- Orchestration logic (pseudo Airflow DAG):

check_arrival = BranchPythonOperator(
    task_id='check_postings_volume',
    python_callable=lambda: 'load_postings' if get_row_count('staging.job_postings_raw') >= 100 else 'alert_low_volume'
)

load_postings = SQLExecuteQueryOperator(
    task_id='load_postings',
    sql='INSERT INTO job_postings_fact SELECT * FROM staging.job_postings_raw;',
    trigger_rule='none_failed'  -- Only runs if check_arrival succeeded
)

alert_low_volume = EmailOperator(
    task_id='alert_low_volume',
    email='data-team@company.com',
    subject='Job postings ETL: insufficient data volume'
)

transform_postings = SQLExecuteQueryOperator(
    task_id='transform_postings',
    sql='UPDATE job_postings_fact SET job_title_short = LOWER(job_title_short);',
    trigger_rule='all_success',
    retries=2,
    retry_delay=timedelta(minutes=5)
)

fallback_snapshot = SQLExecuteQueryOperator(
    task_id='fallback_to_previous_snapshot',
    sql='INSERT INTO job_postings_fact SELECT * FROM job_postings_fact_prev_day;',
    trigger_rule='upstream_failed'  -- Runs only if transform_postings failed after retries
)

mark_degraded = SQLExecuteQueryOperator(
    task_id='mark_load_degraded',
    sql="UPDATE job_metadata SET load_status = 'degraded' WHERE load_date = CURRENT_DATE;",
    trigger_rule='all_done'  -- Runs regardless, but only updates if fallback was used
)

check_arrival >> [load_postings, alert_low_volume]
load_postings >> transform_postings >> [fallback_snapshot, mark_degraded]
fallback_snapshot >> mark_degraded
```

## Notes

- **Trigger rule trap:** `all_success` blocks an entire downstream branch if any sibling fails; use `none_failed` to tolerate one parallel failure path, or branch explicitly to separate success/failure logic.
- **Retry and recovery:** Combine `retries` + `retry_delay` with `upstream_failed` triggers to distinguish "exhausted retries" from "never attempted"—without this, a failed task looks identical to a skipped one.
- **Data quality gates:** Use branching (not trigger rules) for yes/no decisions (volume checks, schema validation); trigger rules are for orchestration (what to run after the branch), not logic.
- **Monitoring trigger outcomes:** Log which trigger rule fired for each task run; most failures happen because the *wrong* trigger fired silently, not because a task failed—audit this in your observability layer.
- **Cross-cutting patterns:** Trigger combinations overlap with idempotency (can a task safely re-run?), backfill windows (which historical periods need retrigger?), and sensor design (do you poll or wait for an event?).
