---
date: 2026-08-24
phase: streaming
topic: Dead letter topics and poison message handling
---

# Dead letter topics and poison message handling

*Streaming and distributed processing*

## Concept

A **dead letter topic** (or dead letter queue) is a separate messaging destination where messages that cannot be processed are sent after exhausting retry attempts. Poison messages—malformed, corrupted, or semantically invalid records—will cause stream processors to crash or stall indefinitely if not isolated. Without dead lettering, a single bad record can block an entire pipeline, causing cascading failures across dependent systems and making root cause analysis nearly impossible.

In streaming contexts, poison messages are especially dangerous because they arrive continuously and out of order. A corrupt JSON payload, a null value in a required field, or a schema violation can arrive at any point in your stream. If your processor throws an exception and retries indefinitely on the same message, the entire pipeline halts. Dead letter topics allow you to acknowledge (and skip) the poisoned message, preserve it for later investigation, and keep the stream moving.

Effective poison message handling requires three layers: (1) **detection**—validation logic that identifies unparseable or invalid data before main processing; (2) **isolation**—routing poisoned messages to a separate topic with original payload and error metadata; (3) **alerting**—monitoring and visibility so poisoned messages don't silently accumulate.

## Practice

**Problem:** A Kafka stream ingests job posting events. Occasionally, `salary_year_avg` arrives as a string instead of an integer, or `job_posted_date` is malformed. Your Spark Structured Streaming job crashes on deserialization. You need to capture bad records, log them, and continue processing valid ones.

```sql
-- Kafka stream deserialization with error handling
-- Pseudo-code showing the pattern in Spark SQL

CREATE TEMPORARY VIEW job_postings_raw AS
SELECT 
  CAST(from_json(value, 'job_id STRING, job_title_short STRING, salary_year_avg STRING, job_work_from_home BOOLEAN, job_posted_date STRING, job_location STRING') AS STRUCT<job_id: STRING, job_title_short: STRING, salary_year_avg: STRING, job_work_from_home: BOOLEAN, job_posted_date: STRING, job_location: STRING>) AS parsed_value,
  value AS raw_payload,
  timestamp,
  CURRENT_TIMESTAMP() AS ingestion_time,
  CASE 
    WHEN parsed_value IS NULL THEN 'JSON_PARSE_ERROR'
    WHEN CAST(parsed_value.salary_year_avg AS INT) IS NULL THEN 'SALARY_TYPE_ERROR'
    WHEN TO_DATE(parsed_value.job_posted_date, 'yyyy-MM-dd') IS NULL THEN 'DATE_PARSE_ERROR'
    ELSE 'VALID'
  END AS validation_status
FROM kafka_source;

-- Write valid records to main topic
INSERT INTO job_postings_fact
SELECT 
  parsed_value.job_id,
  parsed_value.job_title_short,
  CAST(parsed_value.salary_year_avg AS INT) AS salary_year_avg,
  parsed_value.job_work_from_home,
  TO_DATE(parsed_value.job_posted_date, 'yyyy-MM-dd') AS job_posted_date,
  parsed_value.job_location
FROM job_postings_raw
WHERE validation_status = 'VALID';

-- Write invalid records to dead letter topic
INSERT INTO job_postings_dead_letter
SELECT 
  raw_payload,
  validation_status AS error_type,
  ingestion_time,
  timestamp
FROM job_postings_raw
WHERE validation_status != 'VALID';
```

## Notes

- **Retry logic must have bounds:** Infinite retries or exponential backoff without a max attempt count will starve other processing. Always set a retry limit before routing to dead letter.
- **Preserve context in dead letters:** Store the original raw message, timestamp, offset, partition, and error details. You'll need this to debug and potentially replay after fixes.
- **Dead letter is not a sink—it's a checkpoint:** Treat dead letter topics as temporary holding areas, not permanent storage. Set up automated alerts and periodic reviews; an unbounded dead letter queue suggests a systemic data quality or schema evolution problem upstream.
- **Schema evolution and backward compatibility:** Many poison messages result from schema changes. Use versioned schemas (Avro, Protobuf) and consider a compatibility layer to gracefully handle missing or extra fields.
- **Related: circuit breakers, observability, and schema registry:** Dead lettering pairs well with circuit breaker patterns (stop accepting if error rate spikes), structured logging with correlation IDs, and a schema registry to catch incompatibilities before they poison the stream.
