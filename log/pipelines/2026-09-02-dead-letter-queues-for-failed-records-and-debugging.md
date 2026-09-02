---
date: 2026-09-02
phase: pipelines
topic: Dead letter queues for failed records and debugging
---

# Dead letter queues for failed records and debugging

*Pipelines and orchestration*

## Concept

A dead letter queue (DLQ) is a dedicated storage location—typically a table, S3 prefix, or message queue topic—where records that fail validation, transformation, or loading are isolated for later inspection. Rather than letting bad records silently drop or halt the entire pipeline, a DLQ captures them with their original values and the error that caused rejection. This separation is crucial: it lets your pipeline continue processing valid records while creating an auditable, debuggable backlog of failures.

Without a DLQ, you face two painful extremes. Either your pipeline fails hard on the first bad record (blocking all downstream processing), or bad data silently corrupts your warehouse and you discover the problem weeks later during analysis. A DLQ forces you to decide: is this record recoverable? Was the error a one-time data quality issue or a schema mismatch? By capturing the raw input, error message, and timestamp, you turn debugging from guesswork into forensics.

## Practice

**Problem:** Your `job_postings_fact` ingestion receives 50,000 records daily. Some records have `salary_year_avg` values that are negative or absurdly high (e.g., 999999999), others have `job_posted_date` in the future. You want to load only valid records to the fact table, but log all rejects with details so the data quality team can investigate.

```sql
-- Create DLQ table to capture failed records
CREATE TABLE job_postings_dlq (
    dlq_id BIGINT PRIMARY KEY DEFAULT nextval('dlq_seq'),
    raw_record JSONB NOT NULL,
    rejection_reason VARCHAR(500) NOT NULL,
    rejection_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source_file_name VARCHAR(255)
);

-- Upsert with validation: insert valid records, route invalid to DLQ
WITH validation AS (
    SELECT 
        job_id, job_title_short, salary_year_avg, job_work_from_home, 
        job_posted_date, job_location,
        CASE 
            WHEN salary_year_avg < 0 THEN 'Negative salary'
            WHEN salary_year_avg > 500000 THEN 'Salary exceeds max threshold'
            WHEN job_posted_date > CURRENT_DATE THEN 'Posted date in future'
            WHEN job_location IS NULL OR job_location = '' THEN 'Missing job_location'
            ELSE NULL 
        END AS error_msg,
        row_to_json(t.*) AS raw_json
    FROM staging.job_postings_raw t
)
INSERT INTO job_postings_fact 
    (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM validation
WHERE error_msg IS NULL
ON CONFLICT (job_id) DO UPDATE SET 
    job_title_short = EXCLUDED.job_title_short,
    salary_year_avg = EXCLUDED.salary_year_avg;

-- Insert rejects into DLQ
INSERT INTO job_postings_dlq (raw_record, rejection_reason, source_file_name)
SELECT raw_json, error_msg, 'daily_ingest_2024-01-15'
FROM validation
WHERE error_msg IS NOT NULL;
```

## Notes

- **Common mistake:** DLQ tables bloat without retention policy. Set a TTL or archive old rejects to cold storage monthly; otherwise you're paying to store failures forever.

- **Error message quality matters.** Store not just "validation failed" but the specific field, threshold, and actual value. Add a `dlq_context` JSONB column with parsed error details for easier aggregation and alerting.

- **Connects to:** circuit breakers and observability—if DLQ insertion rate spikes (e.g., 10× normal), that's a signal to pause the pipeline and page someone. Instrument DLQ counts in your monitoring dashboard.

- **Replayability:** Keep raw_record in its original format (JSON, CSV, Avro) so you can replay after fixing upstream transformations. Version your validation rules alongside the DLQ entry so you know *which* rules rejected each record.

- **Worth revisiting:** how to handle "soft" vs. "hard" failures (e.g., a missing optional field vs. a corrupted date). Some teams use multiple DLQ tables or severity levels; others implement a `retry_count` column and reprocess DLQ records on schedule.
