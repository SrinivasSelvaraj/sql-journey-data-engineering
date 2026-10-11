---
date: 2026-10-11
phase: pipelines
topic: Sensor tasks and external system polling
---

# Sensor tasks and external system polling

*Pipelines and orchestration*

## Concept

Sensor tasks poll external systems at regular intervals to detect state changes—new files arriving, API endpoints becoming available, database records changing—and trigger downstream workflows only when conditions are met. They're essential when you cannot rely on push notifications or webhooks, or when you need to verify system readiness before a pipeline runs. Without them, pipelines either run blindly into failures (trying to read files that don't exist yet) or waste compute repeatedly checking for work that hasn't arrived.

The key tension: polling is inefficient and introduces latency, but it's often the only reliable option with legacy systems, file-drop architectures, or APIs without event streaming. A well-designed sensor task should be lightweight, idempotent, and explicit about what state it's waiting for—it fails loudly if the condition can't be verified, and the orchestrator (Airflow, dbt Cloud, Dagster) decides whether to retry, skip, or alert.

Sensor tasks also enforce observability: by logging *what* they checked and *when*, they create an audit trail. When a pipeline eventually fails downstream because data arrived malformed, you can trace back and see exactly when the sensor detected it and what assumptions it validated.

## Practice

**Problem:** A job board ingests new postings daily via a CSV file dropped into cloud storage by an external recruiter system. The pipeline must wait until the file arrives and contains at least 100 rows before attempting to load it into `job_postings_fact`. If the file is incomplete or missing after 2 hours, the pipeline should fail loudly with a clear message.

```sql
-- Sensor check (pseudo-code in SQL):
-- 1. Query the external system or metadata layer to detect file arrival
SELECT 
  COUNT(*) as row_count,
  MAX(file_modified_timestamp) as last_updated
FROM external_data_source.job_postings_raw
WHERE file_modified_timestamp >= CURRENT_DATE()
  AND file_modified_timestamp < CURRENT_DATE() + INTERVAL '1 day';

-- Expected behavior:
-- - If row_count >= 100 AND last_updated is recent: sensor succeeds, pipeline proceeds
-- - If row_count < 100 or file not found: sensor retries (up to 120 minutes)
-- - After timeout: sensor fails with error "File not found or incomplete by deadline"

-- Once sensor succeeds, the load task can safely run:
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  ROW_NUMBER() OVER (ORDER BY file_row_id) as job_id,
  position_title as job_title_short,
  CAST(salary_range_max as NUMERIC) as salary_year_avg,
  remote_eligible as job_work_from_home,
  CAST(posting_date as DATE) as job_posted_date,
  office_location as job_location
FROM external_data_source.job_postings_raw
WHERE file_modified_timestamp >= CURRENT_DATE()
ORDER BY file_row_id;
```

## Notes

- **Timeout discipline:** Always set explicit timeout windows on sensors. Open-ended polling drains orchestrator resources and masks true failures under "still waiting." 2–4 hours is common for batch jobs; seconds for real-time sensors.
- **Sensor state is pipeline state:** Log sensor queries and results in the orchestrator run record (Airflow XCom, Dagster I/O managers). Future you debugging a late pipeline run needs to know exactly what the sensor checked.
- **Idempotency matters:** A sensor that rechecks the same condition 50 times must reach the same conclusion each time, or the pipeline becomes non-deterministic. Avoid sensors that mutate state or depend on wall-clock time in subtle ways.
- **Adjacent topics:** Connects tightly to data quality gates (sensors validate structure before load), backfill strategies (sensors help catch historical data), and alerting (sensor timeout should trigger a Slack/PagerDuty message, not silent retry loops).
- **Revisit:** Compare sensor polling against webhooks/event-driven patterns; sometimes the external system *does* support push, and polling is legacy debt masquerading as necessity.
