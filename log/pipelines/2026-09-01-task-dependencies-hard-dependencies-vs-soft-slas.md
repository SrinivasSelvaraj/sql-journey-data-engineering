---
date: 2026-09-01
phase: pipelines
topic: Task dependencies: hard dependencies vs soft SLAs
---

# Task dependencies: hard dependencies vs soft SLAs

*Pipelines and orchestration*

## Concept

A **hard dependency** is a blocking constraint: task B cannot start until task A completes successfully. Without it, downstream jobs operate on incomplete or stale data, producing silent failures that corrupt analytics. Hard dependencies are your contract—they prevent a reporting dashboard from running before source tables are loaded, or prevent model training before feature engineering finishes.

A **soft SLA** is a time-based expectation without a hard block. Task B can start whether or not task A has completed, but monitoring should alert if A misses its SLA window. Soft SLAs are useful when occasional delays are tolerable—e.g., enrichment data arriving 2 hours late is annoying but not catastrophic, so you let the pipeline proceed and re-run the dependent job once enrichment lands.

The distinction matters because hard dependencies ensure correctness at the cost of latency, while soft SLAs optimize throughput at the cost of complexity and operational visibility. Most production pipelines need both: hard dependencies on critical paths (data quality gates, fact table loads) and soft SLAs on optional enrichment. Conflating them—treating everything as hard—creates brittle pipelines that fail on minor delays; treating everything as soft leaves data quality unguarded.

## Practice

**Problem:** You have a `job_postings_fact` table populated daily at 06:00 UTC. A downstream salary reporting job runs at 07:00 UTC and must never run on stale data. However, a secondary job that appends competitive intelligence metadata can tolerate up to 4-hour delays without blocking the salary report. How do you model both constraints?

```sql
-- Hard dependency: Salary report explicitly waits for fact table refresh
-- Orchestration DAG pseudo-code (Airflow/dbt Cloud)

task_load_job_postings_fact = PythonOperator(
    task_id='load_job_postings_fact',
    python_callable=load_facts,
    sla=timedelta(hours=1)  -- Alert if not done by 07:00
)

task_salary_report = PythonOperator(
    task_id='salary_report',
    python_callable=run_salary_analytics,
    upstream_list=[task_load_job_postings_fact]  -- HARD DEPENDENCY
)

-- Soft SLA: Competitive intel job runs independently, monitored separately
task_enrich_competitive_data = PythonOperator(
    task_id='enrich_competitive_data',
    python_callable=enrich_salaries,
    sla=timedelta(hours=4),  -- Alert if not done by 10:00, but don't block
    trigger_rule='none_failed_or_skipped'  -- Doesn't affect downstream
)

-- Re-run salary report only if enrichment eventually lands
task_salary_report_refresh = PythonOperator(
    task_id='salary_report_refresh',
    python_callable=run_salary_analytics,
    upstream_list=[task_enrich_competitive_data],
    trigger_rule='all_done'  -- Runs after enrichment, whatever the state
)

-- Monitoring query to detect soft SLA violations
SELECT 
    job_id, 
    job_posted_date,
    MAX(updated_at) as last_enrichment_time,
    CURRENT_TIMESTAMP - MAX(updated_at) as hours_stale
FROM job_postings_fact
WHERE last_enrichment_time IS NULL 
  AND job_posted_date > CURRENT_DATE - 1
GROUP BY job_id, job_posted_date
HAVING hours_stale > INTERVAL '4 hours'
ORDER BY hours_stale DESC;
```

## Notes

- **Mistake: Over-specifying hard dependencies.** Making every job dependent on every upstream task creates a critical path so long that 1% failure rate guarantees daily downtime. Use hard deps only on data quality gates and the critical path to your primary deliverable.

- **Mistake: Silent soft SLA breaches.** Setting a soft SLA without alerting or re-triggering downstream jobs is theatre—you're documenting a problem, not solving it. Pair soft SLAs with either alerts sent to on-call or automatic re-run logic.

- **Adjacent topic: Trigger rules and idempotency.** Soft SLAs only work if your jobs are idempotent—re-running a salary report on day 2 after enrichment arrives shouldn't duplicate rows. Orchestration frameworks (Airflow `trigger_rule`, dbt `on-run-end`) let you express "retry if upstream recovers," but your SQL must be side-effect-free.

- **Reconnects to: Observability and data contracts.** Hard dependencies encode a contract (this data is ready). Soft SLAs encode an expectation. Both must be monitored and surfaced in dashboards so you know when the pipeline is operating outside its intended mode.

- **Worth revisiting: Circuit breakers and fallback paths.** After multiple soft SLA misses, should you fail fast or fall back to yesterday's data? Define this explicitly in your orchestration strategy rather than letting it emerge as chaos.
