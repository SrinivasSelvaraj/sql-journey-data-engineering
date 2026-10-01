---
date: 2026-10-01
phase: reliability
topic: Root cause analysis: the five whys and fishbone
---

# Root cause analysis: the five whys and fishbone

*Quality, reliability and the professional layer*

## Concept

Root cause analysis (RCA) is the discipline of asking "why" repeatedly—not defensively, but systematically—until you reach the true cause rather than the symptom. The Five Whys is the simplest form: surface symptom → why → why → why → why → root cause. The fishbone (Ishikawa) diagram organizes potential causes into categories: people, process, tools, data, environment. Without RCA, you patch symptoms: you restart a job, add more memory, increase timeouts. With RCA, you discover the job crashes because a downstream system returns malformed JSON on Thursdays, which your parser doesn't handle, which happened because no one validated the contract after their API change.

This matters most when you own a pipeline end-to-end. You're no longer just building; you're explaining to stakeholders why data was wrong, defending SLA compliance, and deciding whether to escalate or solve locally. Ownership means stopping at root cause, not at "the job failed."

Without RCA, pipelines accumulate brittle patches, tribal knowledge lives in Slack, and the same bug surfaces three times under different names. You become reactive, not reliable.

## Practice

**Problem:** A daily job loads job postings into `job_postings_fact`. For the past week, salary_year_avg contains NULLs for 15% of new rows, but the upstream API returns valid numbers. The job doesn't fail; it completes successfully. Analysts notice the data quality drop.

```sql
-- Five Whys investigation:
-- 1. Why are salaries NULL? → The ETL isn't parsing them.
-- 2. Why isn't the parser working? → The JSON schema changed.
-- 3. Why did it change without notification? → No contract validation.
-- 4. Why no validation? → The extraction layer doesn't test upstream.
-- 5. Why not? → No ownership boundary defined between teams.

-- Root cause fix: validate contract, then fix extraction.
WITH raw_extract AS (
  SELECT 
    job_id,
    SAFE.INT64(JSON_EXTRACT_SCALAR(payload, '$.salary_usd')) AS salary_year_avg
  FROM raw_job_api_responses
  WHERE _load_date = CURRENT_DATE()
)
SELECT 
  job_id,
  salary_year_avg
FROM raw_extract
WHERE salary_year_avg IS NOT NULL
UNION ALL
SELECT 
  job_id,
  NULL AS salary_year_avg
FROM raw_extract
WHERE salary_year_avg IS NULL
  AND REGEXP_CONTAINS(JSON_EXTRACT_SCALAR(payload, '$.salary_usd'), r'^\d+$') = FALSE
-- Log the schema violation, alert, and quarantine until resolved.
```

## Notes

- **Common mistake:** Stopping at "the parser failed" instead of asking why it failed. The parser didn't break; the contract changed. Know the difference.
- **Fishbone categories for data pipelines:** People (who owns validation?), Process (do we test contracts?), Tools (does the framework log why parsing failed?), Data (is the upstream format stable?), Environment (did a deployment change assumptions?).
- **Adjacent topics:** SLO/SLA tracking (you can't own what you don't measure), observability and logging (RCA lives in logs), and incident postmortems (blameless culture makes people report problems, not hide them).
- **Revisit:** The difference between "what happened" (incident) and "why it happened and how we prevent it" (RCA). One is narrative; the other is systems thinking. Ownership demands the second.
