---
date: 2026-10-19
phase: streaming
topic: Temporal joins: enriching events with historical dimensions
---

# Temporal joins: enriching events with historical dimensions

*Streaming and distributed processing*

## Concept

A temporal join enriches an event (fact) with dimension attributes that were valid at the time the event occurred, not at query time. When you join a fact table to a dimension table, you typically match on a key; with temporal joins, you also match on time—selecting the dimension record whose validity period contains the event's timestamp. This matters in streaming because dimensions change constantly (a job title gets updated, a location changes, a salary band shifts), and you need the *historical* version that was true when the event happened, not the current version.

Without temporal joins, you get dimension creep: either you overwrite history (losing what was true before), or you duplicate dimension records and lose the time context that ties them to specific facts. In real-time systems, late-arriving or out-of-order events become impossible to enrich correctly because you no longer have access to the dimension state from their original timestamp. This breaks audit trails, ML feature pipelines, and any analysis that depends on "what was the salary range when this person applied?"

## Practice

**Problem:** You have a stream of job applications arriving throughout the day. Each application event carries a `job_id` and an `application_timestamp`. You need to enrich each application with the job title, salary, and remote status *as they appeared on the date the application was submitted*—but the job posting details may have been updated since then. How do you join the application to the correct version of the job posting?

```sql
-- Assume job_postings_scd (slowly changing dimension with valid_from, valid_to dates)
WITH job_postings_scd AS (
  SELECT 
    job_id, 
    job_title_short, 
    salary_year_avg, 
    job_work_from_home,
    job_posted_date AS valid_from,
    COALESCE(next_job_posted_date, CAST('2099-12-31' AS DATE)) AS valid_to
  FROM job_postings_fact
  WINDOW OVER (PARTITION BY job_id ORDER BY job_posted_date) AS next_job_posted_date
)
SELECT 
  app.application_id,
  app.application_timestamp,
  app.job_id,
  jp.job_title_short,
  jp.salary_year_avg,
  jp.job_work_from_home
FROM applications app
INNER JOIN job_postings_scd jp
  ON app.job_id = jp.job_id
  AND CAST(app.application_timestamp AS DATE) BETWEEN jp.valid_from AND jp.valid_to;
```

## Notes

- **State management is hard:** in streaming, you must maintain dimension snapshots indexed by both key and valid time—a state store with two dimensions. Flink, Spark Structured Streaming, and Kafka Streams all require explicit state management logic here.
- **Late arrivals and out-of-order events:** if an event arrives with a timestamp from days ago, you need to look up the dimension state from that past date. Without versioned dimensions, this is impossible; with them, your join becomes a time-travel lookup.
- **SCD (Slowly Changing Dimensions) Type 2 is your friend:** maintain `valid_from` and `valid_to` timestamps on every dimension record. Type 1 (overwrite) loses history; Type 2 preserves it and enables temporal joins.
- **Adjacent topics:** dimension broadcast (ensuring dimension state reaches all workers), watermarking and allowed lateness (defining when you stop accepting late events for join), and interval joins (joining two streams within a time window).
- **Revisit the math:** temporal joins have O(1) lookup cost if your state store is a KV map keyed by `(dimension_key, timestamp_range)`, but you must design range queries carefully to avoid scanning the entire history for every event.
