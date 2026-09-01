---
date: 2026-09-01
phase: pipelines
topic: De-duplication logic: by key, timestamp or custom rule
---

# De-duplication logic: by key, timestamp or custom rule

*Pipelines and orchestration*

## Concept

De-duplication is the removal of redundant records that represent the same logical entity. In pipelines, duplicates arise from idempotency failures, late-arriving data, upstream retries, or join explosions. Without explicit de-duplication logic, you inflate metrics, corrupt aggregations, and lose data integrity—a silent killer because duplicate rows don't always fail loudly.

The three main strategies are: *by key* (keep first/last occurrence of a primary key), *by timestamp* (resolve conflicts using a recency rule), and *by custom rule* (apply business logic like "highest salary wins" or "most complete record wins"). The choice depends on your data semantics—whether duplicates should reflect different states of the same entity or represent genuinely independent records.

De-duplication belongs early in your pipeline, after ingestion but before aggregation and joins. Placing it late masks upstream problems; placing it too early discards signals you might need. The strategy must be repeatable and deterministic so re-runs produce identical results.

## Practice

**Problem:** Your job_postings_fact table is loaded daily from a source system that sometimes sends the same job posting twice (same job_id, possibly different timestamps or salary values). You need to keep only one record per job_id, preferring the most recently posted or updated record, but ensuring deterministic output if timestamps tie.

```sql
WITH ranked_postings AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ROW_NUMBER() OVER (
      PARTITION BY job_id 
      ORDER BY job_posted_date DESC, job_id ASC
    ) AS rn
  FROM job_postings_fact
)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM ranked_postings
WHERE rn = 1;
```

The `ROW_NUMBER()` window function ranks duplicates by job_id, ordering by recency (DESC) and then by job_id (ASC) as a tie-breaker to guarantee determinism.

## Notes

- **Mistake: applying dedup too late.** If you de-duplicate after a GROUP BY or JOIN, you've already inflated row counts and metrics. De-dup at ingestion or right after.
- **Mistake: non-deterministic tie-breaking.** Using `RANDOM()` or omitting a secondary sort order means re-runs produce different results. Always add a deterministic tie-breaker like ID or timestamp.
- **Idempotency connection.** De-duplication is essential for idempotent pipelines—re-running a step shouldn't double-count records. Store dedup state (e.g., a processed timestamp) to avoid re-processing.
- **Test with NULL values.** When ranking by timestamp, NULLs sort unpredictably. Decide: are NULLs treated as "missing" (sort last) or as valid values? Explicit `COALESCE()` protects you.
- **Adjacent: incremental loads & SCD Type 2.** Slowly Changing Dimension patterns use de-duplication combined with validity dates. De-dup-by-key is the first step before deciding which version to keep.
