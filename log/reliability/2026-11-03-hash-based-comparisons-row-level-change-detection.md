---
date: 2026-11-03
phase: reliability
topic: Hash-based comparisons: row-level change detection
---

# Hash-based comparisons: row-level change detection

*Quality, reliability and the professional layer*

## Concept

Hash-based row comparisons enable you to detect whether a record has genuinely changed without comparing every column individually. By computing a hash (MD5, SHA256) of all or specific columns, you create a fingerprint that changes only when the underlying data changes. This is the difference between asking "did *anything* change?" (one comparison) versus "did *any of these 12 columns* change?" (twelve comparisons).

This matters most in slowly-changing dimension (SCD) pipelines, incremental loads, and audit systems where you need to distinguish between "no change" and "real change"—especially when a source system might resend rows without modification, or when you're detecting whether to create a new version of a record. Without it, you either over-capture trivial updates (bloating history tables and wasting storage) or under-capture real changes (missing audit trails).

The brittleness shows up when NULLs, whitespace, or type coercion slip through: a hash of `CONCAT(col1, col2)` will treat NULL differently than `CONCAT_WS()`, and comparing hashes across systems with different collations or decimal precision will fail silently. Professional ownership means making these decisions explicit and testable.

## Practice

**Problem:** You maintain a `job_postings_fact` table that is refreshed daily from a source API. The source re-sends all job postings regardless of whether they changed. You need to identify which rows have *actually* changed (title, salary, work-from-home status, or location) so you can log only real updates to an audit table and avoid spurious SCD Type 2 records.

```sql
WITH source_data AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    MD5(CONCAT(
      COALESCE(job_title_short, ''),
      '|',
      COALESCE(CAST(salary_year_avg AS VARCHAR), ''),
      '|',
      COALESCE(CAST(job_work_from_home AS VARCHAR), ''),
      '|',
      COALESCE(job_posted_date, ''),
      '|',
      COALESCE(job_location, '')
    )) AS row_hash
  FROM raw.job_postings_api
),
current_state AS (
  SELECT job_id, row_hash
  FROM job_postings_fact
)
SELECT
  s.job_id,
  s.job_title_short,
  s.salary_year_avg,
  s.job_work_from_home,
  s.job_posted_date,
  s.job_location,
  CASE WHEN c.row_hash IS NULL OR c.row_hash != s.row_hash
    THEN 'CHANGED'
    ELSE 'UNCHANGED'
  END AS change_status
FROM source_data s
LEFT JOIN current_state c USING (job_id)
WHERE c.row_hash IS NULL OR c.row_hash != s.row_hash;
```

## Notes

- **NULL handling is not optional:** `CONCAT` stops at the first NULL; use `CONCAT_WS` or `COALESCE` consistently, or your hash will be unreliable. Document your choice in the pipeline.
- **Store the hash in your fact table:** Add a `row_hash` column to `job_postings_fact` so downstream comparisons don't recompute. This is a small denormalization that pays for itself in clarity and speed.
- **Hash collisions are theoretically possible but practically irrelevant for row-level work.** MD5 is fine for change detection; save SHA256 for cryptographic contexts.
- **This connects to SCD Type 2 logic, watermarking strategies, and materialized view refresh patterns**—hash comparison is often the gate that decides whether to INSERT a new version or UPDATE the existing record.
- **Revisit when source schema changes:** If a new column is added to the source, update the hash definition and handle the backfill explicitly. Undocumented hash changes silently break comparisons.
