---
date: 2026-10-12
phase: pipelines
topic: Prefect state machine: running, completed, failed states
---

# Prefect state machine: running, completed, failed states

*Pipelines and orchestration*

## Concept

Prefect's state machine defines the lifecycle of task and flow runs through discrete, observable states: **running** (actively executing), **completed** (finished successfully), and **failed** (execution error occurred). Each state transition is deterministic and logged, creating an auditable record of what happened and when. This matters because orchestration without clear state visibility means you can't reliably answer "did this task actually finish?" or "where exactly did it break?"—leading to silent failures, duplicate work, or data inconsistency.

The state machine prevents catastrophic ambiguity. Without it, a task might hang indefinitely while you assume it succeeded, or a downstream task might start before its dependency finishes, corrupting your data pipeline. Prefect's states also enable automatic retries only on `Failed` states (not `Completed`), safe idempotency checks, and human intervention at decision points. If you skip explicit state handling, you lose the ability to distinguish between "task crashed and needs retry" versus "task finished but produced bad data"—both look like downstream failures.

## Practice

**Problem:** Your pipeline loads job postings into `job_postings_fact` from an API. The API sometimes returns partial data or times out. You need to ensure: (1) rows aren't inserted twice if a task reruns, (2) you only mark the load complete if all rows passed validation, and (3) failed rows are logged separately for investigation.

```sql
-- Create a staging table to hold raw API data with state tracking
CREATE TABLE job_postings_staging (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  load_attempt_id UUID,
  validation_status VARCHAR,
  inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- On task RUNNING: insert raw data with attempt ID and 'pending' status
INSERT INTO job_postings_staging 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, load_attempt_id, validation_status)
VALUES (?, ?, ?, ?, ?, ?, gen_random_uuid(), 'pending');

-- On task COMPLETED: validate and atomically move to fact table
BEGIN;
  UPDATE job_postings_staging 
  SET validation_status = CASE 
    WHEN salary_year_avg > 0 AND job_location IS NOT NULL THEN 'valid'
    ELSE 'invalid'
  END
  WHERE load_attempt_id = ?;
  
  INSERT INTO job_postings_fact 
    (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
  FROM job_postings_staging
  WHERE load_attempt_id = ? AND validation_status = 'valid'
  ON CONFLICT(job_id) DO NOTHING;
  
COMMIT;

-- On task FAILED: query staging to log what didn't make it
SELECT job_id, job_location, validation_status
FROM job_postings_staging
WHERE load_attempt_id = ? AND validation_status IN ('invalid', 'pending');
```

## Notes

- **Idempotency trap:** `ON CONFLICT DO NOTHING` prevents duplicates on reruns, but only if your task is truly stateless—if it deletes staging rows on success, a rerun will see no data and incorrectly report completion.
- **State ≠ result:** A task can transition to `Completed` but produce corrupt data if validation logic is weak. Prefect's state tracks execution health, not data quality; add explicit validation gates before you mark success.
- **Adjacent topic:** Prefect's `task_run_context()` lets you inspect current state and attempt number inside your task—use this to conditionally skip retries or log differently on nth failure.
- **Common mistake:** Logging only on `Failed` state. Log on `Running` (to track start time and inputs) and `Completed` (to record row counts, checksums) so you can debug why a successful run produced wrong results.
- **Revisit:** Flow-level error handlers and catch blocks—they let you transition to `Completed` with side effects (like alerting) even after a child task fails, decoupling notification logic from state machine logic.
