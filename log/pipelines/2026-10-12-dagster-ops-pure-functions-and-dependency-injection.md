---
date: 2026-10-12
phase: pipelines
topic: Dagster ops: pure functions and dependency injection
---

# Dagster ops: pure functions and dependency injection

*Pipelines and orchestration*

## Concept

A Dagster op is a pure function when it has no side effects beyond its declared inputs and outputs—it doesn't read from external state, modify globals, or call non-deterministic services directly. This matters because pure ops make your DAG deterministic, testable, and safe to retry. If an op silently depends on a database connection, API client, or config file loaded at import time, a retry or re-execution in a different context fails mysteriously or produces different results.

Dependency injection in Dagster decouples your op logic from infrastructure concerns by passing resources, config, and context explicitly. Instead of an op opening its own database connection, you inject a resource (like a database pool) via the `context` parameter or as a decorated argument. This pattern ensures ops remain pure: their behavior depends only on their declared inputs, not on hidden external state.

Without this discipline, your pipelines become fragile. A rerun fails because the injected resource is stale. A test suite can't isolate ops. A deployment to a new environment crashes because hardcoded credentials no longer exist. Pure functions + dependency injection turn these silent failures into loud, obvious ones that force you to design systems that explain themselves.

## Practice

**Problem:** You have a `job_postings_fact` table and need to load it, filter for high-paying remote jobs, enrich each row with sentiment analysis from an external API, and write results to a new table. The op that calls the API currently hardcodes the API key and makes synchronous requests, making it untestable and fragile on retry.

```sql
-- Bad (impure): op reads API_KEY from environment, makes external call inside op logic
-- Good (pure): op receives api_client resource via context, returns data that depends only on input rows

-- Schema:
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR,
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR
);

-- Query the input data; the op receives this as an input asset/table
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg > 120000
ORDER BY job_posted_date DESC;

-- In Dagster:
-- @op
-- def enrich_remote_jobs(context, high_paying_jobs_df) -> DataFrame:
--     api_client = context.resources.sentiment_api  # injected, not hardcoded
--     return high_paying_jobs_df.assign(
--         sentiment=high_paying_jobs_df['job_title_short'].apply(
--             lambda title: api_client.analyze(title)  # pure: same input → same output
--         )
--     )
```

## Notes

- **Common mistake:** Calling `requests.get()` or `psycopg2.connect()` directly inside an op. Move all I/O to resources and pass them via `context`.
- **Testing:** Pure ops are trivial to unit test—pass in a DataFrame, check the output. Impure ops require mocking and environment setup, hiding bugs until production.
- **Retries and idempotency:** A pure op with deterministic inputs can be safely retried or cached. An op that reads the current time or a live API response will produce different results on retry, breaking idempotent re-execution.
- **Related topics:** Resources (how you inject dependencies), assets (how ops define and depend on data), and sensors (which monitor external state and trigger ops cleanly).
- **Revisit:** The distinction between op inputs (data flowing through the DAG) and op resources (infrastructure flowing into the op). Mixing them is the root cause of impurity.
