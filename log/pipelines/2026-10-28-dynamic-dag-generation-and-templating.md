---
date: 2026-10-28
phase: pipelines
topic: Dynamic DAG generation and templating
---

# Dynamic DAG generation and templating

*Pipelines and orchestration*

## Concept

Dynamic DAG generation means building your directed acyclic graph of tasks at runtime based on configuration, metadata, or external state—rather than hardcoding every task. In Airflow, this typically uses loops or factory functions to create operators programmatically. It matters because real pipelines rarely have static structures: you might need to process dozens of data sources with identical logic, scale a transformation across new tables without editing code, or adjust parallelism based on data volume. Without it, you either duplicate code dangerously or maintain brittle templates that break when requirements shift.

Templating pairs with dynamic DAG generation to make tasks parameterizable. Airflow's Jinja2 templating lets you inject variables (dates, table names, thresholds) into SQL, bash commands, or Python functions without rewriting task logic. The risk of skipping this: task definitions become sprawling conditional blocks, environment-specific values leak into code, and retrying a historical run requires manual tweaking rather than clean re-execution.

## Practice

**Problem:** You need to refresh `job_postings_fact` daily, but also backfill historical windows (30, 60, 90 days) for exploratory analysis. The three windows use identical filtering and aggregation logic—only the date range changes. Without templating, you'd copy-paste the transformation three times; without dynamic DAG generation, you'd hardcode three separate tasks.

```sql
-- Dynamic template: accepted as task parameter {{ window_days }}
-- Backfill runs this once per window; daily run uses window_days=1

WITH filtered_postings AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM raw.job_postings
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '{{ window_days }} days'
    AND salary_year_avg IS NOT NULL
)
INSERT INTO job_postings_fact
SELECT * FROM filtered_postings
ON CONFLICT (job_id) DO UPDATE SET
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_work_from_home = EXCLUDED.job_work_from_home
WHERE job_postings_fact.job_posted_date < EXCLUDED.job_posted_date;
```

In your Airflow DAG, use a loop to generate one task per window:
```python
for window in [1, 30, 60, 90]:
    task = PythonOperator(
        task_id=f'refresh_postings_window_{window}d',
        op_kwargs={'window_days': window, 'sql_template': sql_query},
        # Jinja renders {{ window_days }} → actual value before execution
    )
```

## Notes

- **Jinja rendering happens at task execution, not DAG parse time**: use `render_template_as_native_obj=True` cautiously; unrendered variables in `op_kwargs` cause silent failures.
- **DAG parsing must stay fast**: avoid database calls or heavy logic in the DAG constructor; fetch metadata once at startup or use SubDagOperator / TaskGroup to defer dynamic decisions.
- **Idempotency + templating = safety**: templated SQL with `ON CONFLICT DO UPDATE` or merge logic ensures reruns don't duplicate or corrupt data, even with partial month backfills.
- **Adjacent patterns**: map tasks / XCom for passing dynamic list lengths between tasks; external task sensors when downstream pipelines depend on variable-length upstream runs.
- **Revisit**: test templated SQL against edge cases (leap years, month-end boundaries, NULL date windows) before production; validate rendered SQL in logs rather than assuming Jinja substitution worked.
