---
date: 2026-09-08
phase: streaming
topic: Dead letter topics for poison pill event handling
---

# Dead letter topics for poison pill event handling

*Streaming and distributed processing*

## Concept

A dead letter topic is a dedicated Kafka topic (or equivalent queue) that captures messages the primary consumer cannot process successfully after exhausting retry logic. A "poison pill" is a malformed, corrupted, or incompatible message that causes repeated processing failures—it blocks the consumer, prevents offset progression, and can halt the entire pipeline. Without dead lettering, you either lose visibility into failures, implement complex manual recovery, or crash your streaming job repeatedly on the same bad message.

Dead lettering matters most when you cannot afford to stop the pipeline for inspection. In production, you send the poison pill to a quarantine topic with metadata (original key, value, exception, timestamp, attempt count), then let the main consumer skip it and continue. This decouples failure handling from real-time processing: downstream teams can investigate asynchronously while your stream keeps moving.

Without dead lettering, a single corrupted event—a null field where a string is expected, a timestamp in the wrong format, or a schema violation—will crash your consumer or cause it to retry infinitely. You lose events silently, your alerts fire without context, and recovery becomes manual and error-prone.

## Practice

**Problem:** A job posting event arrives with a malformed `salary_year_avg` value (e.g., a string "N/A" instead of an integer, or a negative number that violates business logic). Your Spark Structured Streaming job tries to cast it, fails, and throws an exception on every micro-batch. The stream stalls; no new job postings are processed.

```sql
-- Dead letter topic schema (side table or separate topic)
CREATE TABLE job_postings_dead_letter (
  dead_letter_id STRING,
  original_message_key STRING,
  original_message_value STRING,
  error_type STRING,
  error_message STRING,
  exception_stacktrace STRING,
  attempted_at TIMESTAMP,
  retry_count INT,
  received_topic STRING
);

-- Main enrichment query with error handling
SELECT
  job_id,
  job_title_short,
  CASE 
    WHEN salary_year_avg < 0 OR salary_year_avg IS NULL THEN -1
    ELSE salary_year_avg
  END AS salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP AS processed_at
FROM job_postings_fact
WHERE 
  -- Skip records that would poison the pipeline
  TRY_CAST(salary_year_avg AS DOUBLE) IS NOT NULL
  AND job_posted_date IS NOT NULL
  AND job_location IS NOT NULL;

-- Insert failed records into dead letter topic
INSERT INTO job_postings_dead_letter
SELECT
  generate_uuid() AS dead_letter_id,
  job_id AS original_message_key,
  TO_JSON(STRUCT(*)) AS original_message_value,
  'VALIDATION_ERROR' AS error_type,
  'salary_year_avg invalid or missing' AS error_message,
  '' AS exception_stacktrace,
  CURRENT_TIMESTAMP AS attempted_at,
  1 AS retry_count,
  'job_postings_fact' AS received_topic
FROM job_postings_fact
WHERE 
  TRY_CAST(salary_year_avg AS DOUBLE) IS NULL
  OR job_posted_date IS NULL
  OR job_location IS NULL;
```

## Notes

- **Offset management:** Ensure your consumer commits offsets *after* routing to dead letter, not before. Otherwise you lose the poison pill entirely. Use Kafka transactions or exactly-once semantics in your framework.
- **Monitoring & alerting:** Dead letter topics are not a "set and forget" solution. Alert on the rate of messages entering dead letter; a spike often signals upstream schema changes or data quality degradation.
- **Adjacent topics:** Relates closely to schema registry (detect schema mismatches early), retry policies (exponential backoff before dead lettering), and data quality frameworks (great Dane, dbt tests, custom validators upstream).
- **Common mistake:** Logging the error but not persisting context—you need the original message, timestamp, and stack trace so a human can investigate why it failed and potentially replay it.
- **Revisit:** How to distinguish between transient errors (retry) vs. permanent errors (dead letter immediately). Consider adding a configurable "poison pill detector" that inspects message size, encoding, or schema before attempting full deserialization.
