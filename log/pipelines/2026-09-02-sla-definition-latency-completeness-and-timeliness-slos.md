---
date: 2026-09-02
phase: pipelines
topic: SLA definition: latency, completeness and timeliness SLOs
---

# SLA definition: latency, completeness and timeliness SLOs

*Pipelines and orchestration*

## Concept

Service Level Agreements (SLAs) define acceptable performance boundaries for data pipelines through measurable objectives. **Latency** measures how fast data moves end-to-end (e.g., "raw events reach the warehouse within 2 hours"); **completeness** ensures no records are silently dropped (e.g., "100% of job postings from source appear in the fact table"); **timeliness** guarantees data freshness by a clock deadline (e.g., "daily jobs finish by 6 AM UTC"). These three SLOs work together: a pipeline can be fast but incomplete, or complete but missed its delivery window.

Without explicit SLOs, teams discover failures reactively—a stakeholder notices missing data at 9 AM, or a batch runs until midnight silently losing 10% of records. SLOs force you to *instrument* pipelines so failures are visible: row count validations, end-to-end runtime assertions, and monotonic freshness checks. This is critical in orchestration because retry logic, backfills, and dependency chains only work if you know what "correct" looks like.

## Practice

**Problem:** Your `job_postings_fact` table must guarantee (1) daily refresh completes by 7 AM, (2) zero loss of new postings from the source, and (3) staleness never exceeds 24 hours. A batch job runs each night, but you have no way to detect if it silently skips 5,000 records or runs at 8:30 AM.

```sql
-- SLO validation queries run after load, before marking data available to consumers

-- Timeliness SLO: last refresh happened within 24 hours
SELECT 
  CASE 
    WHEN MAX(job_posted_date) < CURRENT_DATE - INTERVAL '1 day' 
    THEN 'FAIL: Data older than 24 hours'
    ELSE 'PASS'
  END AS timeliness_check
FROM job_postings_fact;

-- Completeness SLO: row count matches source and no nulls in critical columns
SELECT 
  COUNT(*) AS loaded_rows,
  COUNT(CASE WHEN job_id IS NULL THEN 1 END) AS null_job_ids,
  CASE 
    WHEN COUNT(*) < (SELECT COUNT(*) FROM source_staging.job_postings) * 0.99
    THEN 'FAIL: Completeness below 99%'
    WHEN COUNT(CASE WHEN job_id IS NULL THEN 1 END) > 0
    THEN 'FAIL: Null primary keys'
    ELSE 'PASS'
  END AS completeness_check
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day';

-- Latency SLO: ingestion lag from source timestamp to warehouse timestamp
SELECT 
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY CAST(CURRENT_TIMESTAMP AS TIMESTAMP) - job_posted_date) AS p95_latency_hours,
  CASE 
    WHEN PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY CAST(CURRENT_TIMESTAMP AS TIMESTAMP) - job_posted_date) 
         > INTERVAL '2 hours'
    THEN 'FAIL: P95 latency exceeds 2 hours'
    ELSE 'PASS'
  END AS latency_check
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day';
```

## Notes

- **Common mistake:** Defining SLOs without understanding cost–effort trade-offs. 100% completeness with sub-minute latency may require 10× infrastructure spend; negotiate realistic targets with stakeholders upfront.
- **Instrumentation is not monitoring:** SLOs define *what to measure*; your orchestrator (Airflow, dbt Cloud, Prefect) needs alert rules that fire when SLOs breach. Build SLO checks as distinct tasks that block downstream consumers if they fail.
- **Timeliness ≠ Latency:** timeliness is clock-based ("done by 7 AM"), latency is duration-based ("completed in under 2 hours"). A slow pipeline can meet timeliness if it starts early; a fast pipeline can miss timeliness if triggered late.
- **Monotonicity matters:** row counts can fluctuate legitimately, but job IDs should only grow; track cumulative max job_id to catch deletions or resets that indicate corruption.
- **Adjacent topics:** connects to data quality frameworks (Great Expectations, dbt tests), backfill strategy (how to reprocess gaps while respecting SLOs), and observability stack (logging job duration, row counts, freshness metrics to a time-series database for alerting).
