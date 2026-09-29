---
date: 2026-09-29
phase: reliability
topic: Reconciliation: row count, sum and hash matching
---

# Reconciliation: row count, sum and hash matching

*Quality, reliability and the professional layer*

## Concept

Reconciliation is the automated validation that data moved correctly between systems. Row count matching ensures no records were silently dropped; sum matching (aggregates like salary totals) detects value corruption; hash matching creates a fingerprint of the entire dataset to catch any row-level alteration. Without these checks, bad data propagates downstream—a pipeline can "succeed" while delivering wrong answers to stakeholders and models.

The difference between a junior pipeline and a production one is this: juniors build transformations; owners build reconciliation around them. A salary ETL might load 50,000 rows perfectly but sum to $2B instead of $1.8B because of a type-casting bug. Row count alone would not catch this. Hash mismatches reveal when a single job posting was modified in transit, which matters for audit trails and compliance.

This is your safety net. It runs after every load, flags mismatches immediately, and blocks downstream consumers from using corrupted data. It's the professional layer because it assumes things *will* break, plans for it, and makes failures visible instead of silent.

## Practice

**Problem:** You load job postings into `job_postings_fact` from a source CSV. You need to validate that the row count, total salary sum, and overall data integrity match between source and target. Write a reconciliation query that compares source vs. loaded data and flags any mismatches.

```sql
-- Reconciliation: source vs. target
WITH source_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COALESCE(SUM(salary_year_avg), 0) AS salary_sum,
    MD5(STRING_AGG(CAST(job_id AS VARCHAR), '|' ORDER BY job_id)) AS data_hash
  FROM staging.job_postings_csv
),
target_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COALESCE(SUM(salary_year_avg), 0) AS salary_sum,
    MD5(STRING_AGG(CAST(job_id AS VARCHAR), '|' ORDER BY job_id)) AS data_hash
  FROM analytics.job_postings_fact
)
SELECT
  s.row_count AS source_rows,
  t.row_count AS target_rows,
  CASE WHEN s.row_count = t.row_count THEN '✓ PASS' ELSE '✗ FAIL' END AS row_match,
  s.salary_sum AS source_salary_sum,
  t.salary_sum AS target_salary_sum,
  CASE WHEN s.salary_sum = t.salary_sum THEN '✓ PASS' ELSE '✗ FAIL' END AS sum_match,
  CASE WHEN s.data_hash = t.data_hash THEN '✓ PASS' ELSE '✗ FAIL' END AS hash_match
FROM source_stats s, target_stats t;
```

## Notes

- **Hash order matters**: Always sort by a unique key (like `job_id`) before hashing; otherwise row reordering causes false failures and erodes trust in the check.
- **Nulls are silent killers**: A column that should have no nulls but does will break sums without warning. Include explicit null counts in reconciliation (`COUNT(*) vs. COUNT(column_name)`).
- **Reconciliation vs. validation**: Reconciliation compares source→target; validation checks business rules (e.g., `salary_year_avg > 0`). Both matter, but they're different layers.
- **Timing and snapshots**: Run reconciliation immediately after load, before any downstream consumption. Log results (pass/fail + timestamps) so you can trace when data went wrong.
- **Precision trap**: Float/decimal arithmetic can cause spurious sum mismatches. Cast to fixed precision or use integer cents; document your choice in the check's comments.
