---
date: 2026-10-19
phase: reliability
topic: Distributed tracing across pipeline stages
---

# Distributed tracing across pipeline stages

*Quality, reliability and the professional layer*

## Concept

Distributed tracing assigns a unique identifier to each data record or batch as it flows through multiple pipeline stages, allowing you to track its lineage and timing across transformations. Without tracing, when a job posting appears malformed in your analytics layer, you cannot determine whether the corruption happened during ingestion, enrichment, deduplication, or aggregation—you only know the end state is wrong.

This becomes critical when pipelines span multiple systems (APIs → Kafka → data lake → warehouse → BI layer) or when jobs run asynchronously with unpredictable latency. A trace ID lets you correlate logs, metric emissions, and intermediate artifacts back to their origin, turning a hours-long debugging session into minutes. It also enables you to measure end-to-end latency by stage, surface which transformations are bottlenecks, and identify systematic data quality failures that only affect specific ingestion windows.

Without tracing, you lose observability the moment your pipeline scales. You cannot distinguish between a slow enrichment service, a blocked network call, or data that was simply invalid upstream. You cannot answer whether salary data for remote jobs is systematically missing or just occasionally delayed. Tracing is the difference between reactive firefighting and proactive ownership.

## Practice

**Problem:** You're loading job postings from an API, deduplicating by job_id, enriching salary data via a lookup service, then loading to the warehouse. A business user reports that 300 postings lack salary_year_avg. You need to determine at which stage they were dropped or nulled, and whether it's a data quality issue or a service failure.

```sql
-- Add trace columns at ingestion
WITH ingested AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    GENERATE_UUID() AS trace_id,
    CURRENT_TIMESTAMP() AS stage_ingested_at,
    'ingestion' AS stage_name,
    COUNT(*) OVER (PARTITION BY job_id) AS dup_count
  FROM raw.job_postings_api
),

-- Track deduplication
deduplicated AS (
  SELECT
    * EXCEPT(dup_count),
    CURRENT_TIMESTAMP() AS stage_deduplicated_at,
    'deduplication' AS stage_name,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) AS dedup_rank
  FROM ingested
  WHERE dup_count = 1 OR ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) = 1
),

-- Track enrichment and log nulls
enriched AS (
  SELECT
    d.*,
    COALESCE(e.salary_year_avg, d.salary_year_avg) AS salary_year_avg_enriched,
    CURRENT_TIMESTAMP() AS stage_enriched_at,
    'enrichment' AS stage_name,
    CASE WHEN e.salary_year_avg IS NULL THEN 'enrichment_lookup_miss' ELSE 'enrichment_success' END AS enrichment_status
  FROM deduplicated d
  LEFT JOIN external_salary_lookup e USING (job_id)
)

-- Final load with trace for warehouse
SELECT
  * EXCEPT(dedup_rank, enrichment_status),
  enrichment_status,
  CURRENT_TIMESTAMP() AS stage_loaded_at,
  'warehouse_load' AS stage_name
FROM enriched
WHERE salary_year_avg_enriched IS NOT NULL
  OR enrichment_status = 'enrichment_lookup_miss';

-- Query to diagnose: where did the 300 go?
-- SELECT trace_id, job_id, stage_name, enrichment_status FROM job_postings_fact 
-- WHERE salary_year_avg IS NULL GROUP BY enrichment_status;
```

## Notes

- **Mistake:** Adding trace IDs only at the final layer. Traces must be generated at ingestion and propagated through every transformation; adding them retroactively is useless.
- **Mistake:** Using non-deterministic IDs (like CURRENT_TIMESTAMP) as traces. Use UUIDs or hash(source_id + batch_timestamp) so replayed jobs produce identical traces.
- **Adjacent topics:** This connects directly to data contracts (trace IDs should flow through your schema versioning), SLA monitoring (end-to-end latency per trace cohort), and alerting (anomalies in enrichment_status ratios).
- **Revisit:** Consider whether traces should be indexed separately for fast diagnostic queries, especially at scale. A dedicated trace log table (trace_id, job_id, stage, duration, status) often outperforms filtering large fact tables.
- **Ownership signal:** The ability to answer "show me all records affected by the enrichment service outage on 2024-03-15" without reconstructing state is what separates operators from caretakers.
