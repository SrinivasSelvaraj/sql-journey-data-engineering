---
date: 2026-08-30
phase: modelling
topic: Surrogate key collision risk and sequence exhaustion
---

# Surrogate key collision risk and sequence exhaustion

*Data modelling and warehousing*

## Concept

A surrogate key is a system-generated identifier (usually an auto-incrementing integer or UUID) used to uniquely identify a row in a fact or dimension table. Collision risk occurs when two different business entities accidentally receive the same surrogate key; sequence exhaustion happens when the key space runs out entirely. Without proper surrogate key design, you risk duplicate keys in your warehouse—causing joins to multiply rows silently, masking data quality issues until they corrupt downstream dashboards and reports.

This matters most in high-volume fact tables and slowly-changing dimensions. A 32-bit integer supports ~2 billion values; a job posting warehouse ingesting thousands of records daily will exhaust this in years. Collisions are harder to detect than exhaustion but far more damaging—a join on a collided key produces spurious results that pass validation because cardinality looks normal. UUID-based keys avoid both risks but add storage and indexing cost.

Without this safeguard, your warehouse silently corrupts. A fact table row with job_id = 5 that should refer to "Senior Engineer" might instead refer to "Data Analyst" after key reassignment or reload, and nobody notices until a report is challenged in a meeting.

## Practice

**Problem:** Your `job_postings_fact` uses a 32-bit `job_id` surrogate key. Ingestion runs nightly; you're loading ~50,000 new postings daily. After 4 years, you'll exhaust the key space. Additionally, if your ETL crashes and reloads a batch, old rows and new rows might be assigned identical keys before deduplication logic runs.

**Solution:** Use a larger key type with collision detection, or add a uniqueness constraint on the natural key:

```sql
CREATE TABLE job_postings_fact (
  job_id BIGINT PRIMARY KEY,  -- 64-bit: ~9.2 quintillion values
  job_title_short VARCHAR(100) NOT NULL,
  salary_year_avg NUMERIC(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE NOT NULL,
  job_location VARCHAR(255) NOT NULL,
  -- Natural key constraint prevents collision on reload
  UNIQUE(job_posted_date, job_location, job_title_short, salary_year_avg),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Monitor sequence exhaustion in advance
SELECT 
  EXTRACT(YEAR FROM created_at) AS year,
  COUNT(*) AS postings_loaded,
  ROUND(100.0 * MAX(job_id) / 9223372036854775807, 4) AS pct_bigint_used
FROM job_postings_fact
GROUP BY EXTRACT(YEAR FROM created_at)
ORDER BY year;
```

## Notes

- **BIGINT vs. UUID:** BIGINT (64-bit) is cheaper to index and join; UUIDs are safer but slower. Choose BIGINT if you can monitor exhaustion; UUID if your retention is permanent and scale unknown.
- **Natural key uniqueness:** Always add a UNIQUE constraint on the business natural key (date + location + title + salary here). Catches reloads, prevents silent collisions.
- **Slowly Changing Dimensions:** Dimension tables often use surrogate keys *and* add `effective_date` and `end_date` columns; a single natural key can have multiple surrogate keys across time (SCD Type 2). Don't conflate the two concepts.
- **Sequence monitoring:** Query `pg_sequences` or `information_schema.tables` monthly to track max assigned value. Set an alert at 80% of theoretical max.
- **Resetting after failure:** Never reuse keys after a failed load. Always regenerate from the current sequence max, not from 1, to avoid collision. Document this in your runbook.
