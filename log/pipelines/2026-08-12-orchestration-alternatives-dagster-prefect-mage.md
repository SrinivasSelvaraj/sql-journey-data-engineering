---
date: 2026-08-12
phase: pipelines
topic: Orchestration alternatives: Dagster, Prefect, Mage
---

# Orchestration alternatives: Dagster, Prefect, Mage

*Pipelines and orchestration*

## Concept

Orchestration tools (Dagster, Prefect, Mage) manage workflow dependencies, retries, and state—they're the difference between a script that fails silently and a pipeline you can trust. Without orchestration, you manually trigger jobs, lose track of what ran, and spend hours debugging whether a downstream failure came from bad data or missing input. Each tool takes a different philosophy: Dagster prioritizes asset lineage and type safety; Prefect emphasizes developer experience and dynamic flows; Mage blends them with a UI-first approach. The core job of any orchestrator is to make failures explicit (loud), recovery deterministic (rerun safely), and traceability automatic (explain themselves).

Choosing between them matters most when your pipeline spans multiple systems, requires conditional logic, or needs audit trails. A single SQL script doesn't need orchestration; a 7-step workflow touching APIs, data lakes, and warehouses does. All three handle retries, dependency graphs, and monitoring, but they differ in learning curve, deployment complexity, and whether you write Python, YAML, or visual DAGs.

## Practice

**Problem:** Your job postings fact table ingests daily from an API, transforms salary data (cleaning outliers, normalizing currency), and loads into the warehouse. If the API fails, the transformation shouldn't run. If transformation succeeds but load fails, you need to retry just the load, not re-fetch from the API. How do you structure this so failures are caught and partial reruns are safe?

```sql
-- Orchestrator manages these as separate assets/tasks with explicit dependencies

-- Task 1: Extract (idempotent, stages raw data)
CREATE TABLE IF NOT EXISTS job_postings_raw (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  api_run_id VARCHAR -- track which API call produced this
);

-- Task 2: Transform (depends on Task 1, validates and cleans)
CREATE TABLE IF NOT EXISTS job_postings_staging (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR,
  validation_status VARCHAR, -- 'pass', 'outlier_cleaned', 'failed'
  transform_run_id VARCHAR
);

INSERT INTO job_postings_staging
SELECT
  job_id,
  job_title_short,
  CASE
    WHEN salary_year_avg > 500000 THEN 500000 -- cap outliers
    WHEN salary_year_avg < 20000 THEN NULL -- flag as invalid
    ELSE salary_year_avg
  END AS salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE
    WHEN salary_year_avg > 500000 OR salary_year_avg < 20000 THEN 'outlier_cleaned'
    ELSE 'pass'
  END,
  '{{ run_id }}'
FROM job_postings_raw
WHERE ingested_at > DATEADD(day, -1, CURRENT_DATE)
  AND api_run_id = '{{ upstream_run_id }}'; -- tie to extract run

-- Task 3: Load (depends on Task 2, idempotent merge)
MERGE INTO job_postings_fact f
USING job_postings_staging s
ON f.job_id = s.job_id AND f.job_posted_date = s.job_posted_date
WHEN MATCHED THEN
  UPDATE SET
    salary_year_avg = s.salary_year_avg,
    job_work_from_home = s.job_work_from_home,
    job_location = s.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (s.job_id, s.job_title_short, s.salary_year_avg, s.job_work_from_home, s.job_posted_date, s.job_location);
```

## Notes

- **Idempotency trap:** If your transform or load isn't idempotent (running twice produces different results), retries become dangerous. Use MERGE, upsert patterns, or unique constraints; avoid INSERT without deduplication logic.

- **Run IDs and lineage:** Pass `run_id` and `upstream_run_id` through your pipeline (shown in SQL comments above) so you can trace which extraction fed which transform; this makes debugging "why is this row wrong?" tractable.

- **Dagster vs. Prefect vs. Mage:** Dagster shines if you care deeply about asset versioning and type hints; Prefect if you want minimal overhead and Pythonic flows; M
