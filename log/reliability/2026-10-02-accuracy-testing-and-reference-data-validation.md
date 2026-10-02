---
date: 2026-10-02
phase: reliability
topic: Accuracy testing and reference data validation
---

# Accuracy testing and reference data validation

*Quality, reliability and the professional layer*

## Concept

Accuracy testing compares output data against known-good reference data to catch transformation errors, business logic mistakes, and silent failures that functional tests miss. It's the difference between "the pipeline ran" and "the pipeline produced correct results." Without it, bad data quietly propagates downstream—wrong salary figures in reports, misclassified jobs, or corrupted dates that fail months later when someone notices the anomaly.

Reference data validation establishes a baseline of truth: historical snapshots, external sources (APIs, vendor feeds, regulatory databases), or manually curated golden datasets. You measure your pipeline's output against this baseline using metrics like row counts, value distributions, checksums, and field-level comparisons. This is where you catch off-by-one errors in job location parsing, salary unit conversions gone wrong, or null handling that silently inflates or deflates your counts.

The professional layer requires this because stakeholders don't care if your DAG succeeded—they care if the numbers are right. Accuracy testing shifts responsibility from "I built it" to "I own this data."

## Practice

**Problem:** Your `job_postings_fact` table is loaded daily. Yesterday's run added 1,247 rows, but your reference dataset (validated externally) shows only 1,089 new postings should exist. Additionally, 23 rows have `salary_year_avg` values below $20,000, which violates business rules (salaries are always market-rate estimates ≥ $20k). How do you detect and flag this?

```sql
-- Accuracy check: row count validation against reference
WITH ref_counts AS (
  SELECT COUNT(*) AS expected_count 
  FROM reference_job_postings 
  WHERE job_posted_date = CURRENT_DATE - 1
),
actual_counts AS (
  SELECT COUNT(*) AS actual_count 
  FROM job_postings_fact 
  WHERE job_posted_date = CURRENT_DATE - 1
)
SELECT 
  actual.actual_count,
  ref.expected_count,
  actual.actual_count - ref.expected_count AS variance,
  CASE WHEN ABS(actual.actual_count - ref.expected_count) > 10 
       THEN 'FAIL: Count variance exceeds threshold'
       ELSE 'PASS' 
  END AS validation_status
FROM actual_counts actual, ref_counts ref;

-- Business rule validation: salary floor
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg,
  'INVALID: Salary below $20k threshold' AS violation
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE - 1
  AND salary_year_avg < 20000
  AND salary_year_avg IS NOT NULL;

-- Value distribution check (spot anomalies)
SELECT 
  job_work_from_home,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE - 1
GROUP BY job_work_from_home;
```

## Notes

- **Silent nulls are deadly:** A missing `salary_year_avg` passes structural validation but breaks downstream analytics. Always validate not just that fields exist, but that they meet cardinality and non-null expectations.
- **Reference data decay:** Golden datasets become stale; establish a refresh cadence and version your reference data (add a `ref_load_date` column). Comparing today's pipeline against 6-month-old truth is worse than useless.
- **Variance thresholds aren't arbitrary:** Tune tolerances based on operational reality. A 2% variance in row counts might be normal; a 15% variance signals a real problem. Document *why* each threshold exists.
- **Connects to:** data contracts (schema + SLAs), observability (alerting on accuracy metrics), and reconciliation patterns (three-way matching with source, reference, and output).
- **Revisit if:** stakeholders report discrepancies, your pipeline scope changes, or you add new transformations. Accuracy tests are living documentation of what "correct" means in your domain.
