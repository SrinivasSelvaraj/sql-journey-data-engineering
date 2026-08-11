---
date: 2026-08-11
phase: pipelines
topic: Change data capture patterns
---

# Change data capture patterns

*Pipelines and orchestration*

## Concept

Change Data Capture (CDC) is a mechanism that identifies and extracts only the rows that have changed—inserted, updated, or deleted—since the last pipeline run, rather than reprocessing the entire dataset. This is essential in data engineering because full table scans become prohibitively expensive at scale: a nightly job reading 500M rows to find 10K changes wastes compute and delays insights.

CDC patterns matter most when source systems are large, frequently updated, or cost-sensitive (e.g., cloud databases charged per scan). Without CDC, you either pay the cost of scanning everything, or you miss updates entirely. Common implementations include log-based CDC (reading database transaction logs), query-based CDC (timestamp or version columns), and event streaming (Kafka topics capturing changes as they occur).

The stakes are high: missing a CDC strategy forces you to choose between accuracy and efficiency. You also lose the ability to explain *why* a metric changed—was it new data or a correction? With proper CDC, you capture the lineage of every change and can replay or debug with confidence.

## Practice

**Problem:** The `job_postings_fact` table receives 50K new postings daily and 10K corrections (salary updates, location changes). A full scan takes 8 minutes; you need to load only changes into your warehouse, deduplicate corrections, and track which rows are new vs. updated.

```sql
-- Assume source has a `last_modified_timestamp` column
-- 1. Query-based CDC: fetch only changed rows since last run
WITH cdc_extract AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    last_modified_timestamp,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY last_modified_timestamp DESC) AS rn
  FROM job_postings_fact
  WHERE last_modified_timestamp > '{{ last_run_timestamp }}'
    AND last_modified_timestamp <= '{{ current_run_timestamp }}'
)
-- 2. Deduplicate: keep only the latest version of each job_id
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  last_modified_timestamp,
  CASE WHEN rn = 1 THEN 'latest' ELSE 'superseded' END AS change_type
FROM cdc_extract
WHERE rn = 1
ORDER BY last_modified_timestamp DESC;
```

## Notes

- **Timestamp pitfall:** Relying on `updated_at` fails during backfills or clock skew; always add idempotency keys (hash of row content) and store `_dbt_valid_from`/`_dbt_valid_to` for SCD Type 2.
- **Rerun safety:** Store the high-water mark (`last_run_timestamp`) in a metadata table, not in code; a crashed pipeline must resume from the last *committed* state, not from an assumption.
- **Related: Event streaming vs. batch CDC**—Kafka/Pulsar give you sub-second freshness but require different orchestration (stateful consumers); batch CDC suits nightly jobs but requires timestamp discipline.
- **Common mistake:** Assuming deletes are captured—most CDC systems track inserts and updates only. Explicit soft deletes (`is_deleted` flag) or CDC-aware sources (Postgres logical decoding) are needed for true delete capture.
- **Revisit:** SCD patterns (slowly changing dimensions), idempotent upserts, and the trade-off between query-based CDC (simple, slow for large tables) and log-based CDC (complex, fast, harder to debug).
