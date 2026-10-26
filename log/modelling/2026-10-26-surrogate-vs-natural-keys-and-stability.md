---
date: 2026-10-26
phase: modelling
topic: Surrogate vs natural keys and stability
---

# Surrogate vs natural keys and stability

*Data modelling and warehousing*

## Concept

A **surrogate key** is a system-generated identifier (e.g., auto-increment integer or UUID) with no business meaning, while a **natural key** is composed of real business attributes that uniquely identify a record (e.g., job posting ID from the source system, or company + job title + posting date). Surrogate keys are **stable by design**—they never change even when underlying data does. Natural keys can become unstable when their defining attributes change: a job title gets reworded, a location code is reassigned, or upstream systems modify their logic.

In warehousing, stability matters because downstream queries and dashboards depend on keys not shifting. If you join on `job_title_short` and someone reruns historical data with normalized titles, your grain changes silently. Surrogate keys isolate you from these surprises. However, they must be generated consistently—rerunning a pipeline must produce identical surrogate keys for identical source records, or you'll create duplicate dimension entries and corrupt fact tables.

The practical trade-off: use surrogate keys in fact tables and slowly-changing dimensions (SCD Type 2) to track history safely. Use natural keys to *identify* the business entity and validate that your surrogate generation is deterministic (hash the natural key if auto-increment is unavailable).

## Practice

**Problem:** Your job postings arrive daily with fields like `job_title_short` and `job_location`. Over time, some postings are re-posted with slightly different titles or location formats. You need a fact table that doesn't duplicate rows when the same logical job is posted again, and you need to track which posting events are distinct.

```sql
-- Dimension: job_posting_dim with stable surrogate key
CREATE TABLE job_posting_dim AS
SELECT
  ROW_NUMBER() OVER (ORDER BY job_posting_natural_key) AS job_posting_sk,
  job_posting_natural_key,  -- e.g., source_system_id + posting_date + company_id
  job_title_short,
  job_location,
  job_work_from_home,
  dbt_valid_from,
  dbt_valid_to,
  is_current
FROM {{ ref('stg_job_postings') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY job_posting_natural_key ORDER BY dbt_valid_from DESC) = 1;

-- Fact: use surrogate key for JOINs, natural key for uniqueness check
CREATE TABLE job_postings_fact AS
SELECT
  jd.job_posting_sk,
  jd.job_posting_natural_key,  -- kept for audit/debugging
  salary_year_avg,
  job_posted_date,
  CURRENT_TIMESTAMP AS loaded_at
FROM {{ ref('stg_job_postings') }} s
LEFT JOIN job_posting_dim jd USING (job_posting_natural_key)
WHERE jd.is_current = TRUE;
```

The surrogate key `job_posting_sk` never changes; if a job is re-listed with a typo fix in `job_title_short`, SCD Type 2 logic creates a new row in the dimension with a new surrogate key, and your fact table remains consistent.

## Notes

- **Deterministic generation is essential**: if you use `ROW_NUMBER()` without `ORDER BY`, reruns produce different surrogates. Hash or sequence the natural key instead, or use `dbt_generated_pk` patterns.
- **Natural key always stays in the warehouse**: even if surrogate keys are your join column, keep the natural key visible for debugging and audits. It's your proof that deduplication worked.
- **SCD strategy must match your domain**: SCD Type 2 (track history with valid_from/valid_to) suits dimensions where attributes change slowly; SCD Type 1 (overwrite) suits lookup tables where only the latest state matters.
- **Watch for composite natural keys**: a job posting identified by (source_id, company_id, posting_date) is stable only if all three elements never conflict. Document this assumption.
- **Connects to**: data lineage (tracking which natural keys map to which surrogates), idempotency (same inputs must produce same surrogates), and slowly-changing dimensions (SCD).
