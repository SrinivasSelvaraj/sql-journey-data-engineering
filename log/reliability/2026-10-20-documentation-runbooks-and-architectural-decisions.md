---
date: 2026-10-20
phase: reliability
topic: Documentation: runbooks and architectural decisions
---

# Documentation: runbooks and architectural decisions

*Quality, reliability and the professional layer*

## Concept

Runbooks and architectural decision records (ADRs) are the artifacts that turn tribal knowledge into organizational capability. A runbook is a step-by-step procedure for operating, debugging, or recovering a data system—written for someone who doesn't know the system yet. An ADR documents *why* a technical choice was made: trade-offs considered, constraints, alternatives rejected, and the decision date. Together, they answer: "What do I do when this breaks at 2 AM?" and "Why did we build it this way instead of that way?"

Without runbooks, incident response becomes archaeological—hunting for the person who built it, discovering undocumented recovery procedures, or worse, applying the wrong fix because the constraints aren't visible. Without ADRs, the system becomes a museum of abandoned decisions: why is this table partitioned by month instead of day? Why does this job retry 3 times instead of 5? Teams waste weeks re-arguing settled decisions or inheriting patterns without understanding their original trade-offs.

This is the difference between owning a system and merely operating it. Ownership means you can onboard someone in hours, not weeks. It means you can confidently make changes because the reasoning is documented. It means you're trusted with systems beyond the ones you personally wrote.

## Practice

**Problem:** The `job_postings_fact` table is queried heavily each morning at 9 AM by the analytics team's dashboards. Some mornings queries timeout; some mornings they don't. You suspect the ETL job that loads this table sometimes finishes late, but you're not sure what normal is, what to check first, or how to manually backfill a missing day.

**Solution (Runbook excerpt):**

```sql
-- RUNBOOK: job_postings_fact Late Load Recovery
-- Use this when morning dashboards report stale data (job_posted_date < today)

-- Step 1: Check ETL job status in last 24 hours
SELECT 
  dag_id, 
  execution_date, 
  state, 
  duration_seconds
FROM airflow_logs
WHERE dag_id = 'load_job_postings_fact'
  AND execution_date >= CURRENT_DATE - INTERVAL 1 DAY
ORDER BY execution_date DESC;

-- Step 2: If state = 'failed', check the error log
-- (See ADR-2024-01-15: Why we retry on timeout vs. fail immediately)
SELECT error_message, log_timestamp 
FROM airflow_logs 
WHERE dag_id = 'load_job_postings_fact' 
  AND state = 'failed'
ORDER BY log_timestamp DESC 
LIMIT 5;

-- Step 3: Manual backfill (only if Step 1 shows no run at all for today)
-- Reload yesterday's raw data into fact table
INSERT INTO job_postings_fact 
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  CURRENT_TIMESTAMP as load_timestamp
FROM raw.job_postings_staging
WHERE job_posted_date = CURRENT_DATE - INTERVAL 1 DAY
  AND load_timestamp >= (SELECT MAX(load_timestamp) FROM job_postings_fact)
ON CONFLICT (job_id) DO UPDATE SET load_timestamp = EXCLUDED.load_timestamp;

-- Step 4: Notify analytics team in #data-alerts Slack channel with query above results
```

## Notes

- **Runbooks must be testable**: Write them as if you're the on-call engineer at 3 AM. Include exact query names, column references, and expected output ranges. "Check the logs" is not a runbook; "SELECT * FROM table WHERE X" is.

- **ADRs prevent decision fatigue**: The job_postings_fact is partitioned by `job_posted_date`, not job_id, because queries almost always filter by recency. This should be documented once, not re-argued when someone suggests re-partitioning.

- **Ownership scales through documentation**: A system with good runbooks and ADRs can be owned by rotating on-call engineers. A system without them becomes a single-person bottleneck.

- **Common mistake**: Writing runbooks *after* an incident, when memory is freshest but adrenaline is high. Write them during calm design phases when you still remember the trade-offs and constraints.

- **Connects to**: monitoring (what alerts trigger the runbook), schema design (ADRs justify partitioning and denormalization choices), and incident postmortems (which should link back to the runbook steps that were unclear or missing).
