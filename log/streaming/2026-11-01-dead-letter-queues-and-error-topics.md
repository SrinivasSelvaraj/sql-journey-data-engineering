---
date: 2026-11-01
phase: streaming
topic: Dead letter queues and error topics
---

# Dead letter queues and error topics

*Streaming and distributed processing*

## Concept

A dead letter queue (DLQ) or error topic is a dedicated stream or queue that captures messages that fail processing in your main data pipeline. When a message cannot be parsed, validated, or processed due to business logic errors, schema violations, or downstream system failures, it's routed to the DLQ instead of being silently dropped or blocking the entire pipeline. This is critical in streaming systems because data arrives continuously and out of order—you cannot pause to manually fix every malformed record without losing velocity and accumulating backpressure.

Without a DLQ, you face a choice: either crash the pipeline on bad data (losing good data behind it), retry infinitely (blocking downstream consumers), or drop records silently (losing observability). A DLQ decouples error handling from the happy path, allowing your main pipeline to remain healthy while you investigate failures asynchronously. Each record in the DLQ typically includes the original payload, the error message, timestamp, and processing context—enabling root cause analysis and replay once fixed.

## Practice

**Problem:** Your streaming job consumes job posting records. Some records have `NULL` salary values, others have unparseable dates in `job_posted_date`, and occasionally the downstream warehouse is unavailable. You need to prevent bad records from blocking good ones while maintaining an audit trail of what failed and why.

```sql
-- Main processing stream (Kafka/Flink/Spark)
WITH validated AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    NULL AS error_reason
  FROM job_postings_raw
  WHERE salary_year_avg IS NOT NULL
    AND TRY_CAST(job_posted_date AS DATE) IS NOT NULL
),
failed AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    CASE
      WHEN salary_year_avg IS NULL THEN 'Missing salary'
      WHEN TRY_CAST(job_posted_date AS DATE) IS NULL THEN 'Invalid date format'
      ELSE 'Unknown error'
    END AS error_reason
  FROM job_postings_raw
  WHERE salary_year_avg IS NULL
     OR TRY_CAST(job_posted_date AS DATE) IS NULL
)
-- Write validated to main topic, failed to DLQ topic
SELECT * FROM validated;  -- → job_postings_fact
SELECT *, CURRENT_TIMESTAMP AS dlq_timestamp FROM failed;  -- → job_postings_dlq
```

## Notes

- **Silent failures are worse than loud ones.** Always log why a message entered the DLQ (schema version mismatch, missing required field, external API timeout) so you can detect systemic issues early.
- **DLQ is not a trash bin.** Treat it as a first-class dataset: monitor its growth rate, set up alerts when it exceeds thresholds, and schedule regular reviews to identify patterns and fix root causes.
- **Replay and idempotency matter.** Design your pipeline so records from the DLQ can be reprocessed without duplicating or corrupting the main dataset; use idempotent keys or transactions where possible.
- **Adjacent: circuit breakers and backpressure.** If a downstream system is down, a DLQ prevents upstream data loss, but you may also need circuit breaker logic to fast-fail and avoid overwhelming retry buffers.
- **Revisit retention policy.** Decide how long to keep DLQ records (30–90 days is common); after that, archive to cold storage or drop them if the root cause is deemed non-actionable.
