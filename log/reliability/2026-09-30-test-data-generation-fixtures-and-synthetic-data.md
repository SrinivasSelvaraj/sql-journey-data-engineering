---
date: 2026-09-30
phase: reliability
topic: Test data generation: fixtures and synthetic data
---

# Test data generation: fixtures and synthetic data

*Quality, reliability and the professional layer*

## Concept

Test data generation is the intentional creation of realistic, reproducible datasets for validating pipelines without touching production. This splits into two strategies: **fixtures** (pre-built, version-controlled datasets for unit and integration tests) and **synthetic data** (procedurally generated data that mimics production distributions, cardinality, and edge cases).

This matters because pipelines fail silently on data they've never seen. A salary aggregation works fine on uniform numeric ranges but breaks on NULLs, negative values, or outliers. A date filter passes on contiguous sequences but fails on sparse or future-dated records. Without deliberate test data, you discover these gaps in production—or worse, never discover them at all.

Without this discipline, you're building blind. You can't verify idempotency, test error handling, validate edge-case logic, or safely refactor without risking silent data corruption. This is the boundary between "works on my laptop" and "trusted to own this in production."

## Practice

**Problem:** The `job_postings_fact` table feeds downstream salary reports and location filters. Your pipeline must handle missing salaries, remote-work tri-state logic, and date ranges spanning years. Build a fixture and a synthetic generator to catch common breakages before they reach production.

```sql
-- FIXTURE: Known edge cases (commit to version control)
CREATE TABLE test_job_postings_fixture AS
SELECT 1 AS job_id, 'Data Engineer' AS job_title_short, 120000 AS salary_year_avg, TRUE AS job_work_from_home, '2024-01-15'::DATE AS job_posted_date, 'San Francisco, CA' AS job_location
UNION ALL
SELECT 2, 'Analyst', NULL, FALSE, '2023-06-01', 'New York, NY'
UNION ALL
SELECT 3, 'Manager', 0, NULL, '2024-12-31', NULL
UNION ALL
SELECT 4, 'Engineer', 150000, TRUE, '2020-01-01', 'Remote'
UNION ALL
SELECT 5, 'Consultant', -5000, FALSE, '2025-06-01', 'Austin, TX';

-- SYNTHETIC: Procedural generation for scale and distribution testing
WITH date_range AS (
  SELECT generate_series('2020-01-01'::DATE, '2025-01-01'::DATE, '1 day'::INTERVAL)::DATE AS posted_date
),
generated AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY posted_date) AS job_id,
    CASE (RANDOM() * 4)::INT
      WHEN 0 THEN 'Data Engineer'
      WHEN 1 THEN 'Analyst'
      WHEN 2 THEN 'Manager'
      ELSE 'Consultant'
    END AS job_title_short,
    CASE WHEN RANDOM() < 0.1 THEN NULL
         ELSE (80000 + (RANDOM() * 100000))::INT END AS salary_year_avg,
    CASE WHEN RANDOM() < 0.3 THEN NULL
         WHEN RANDOM() < 0.6 THEN TRUE
         ELSE FALSE END AS job_work_from_home,
    posted_date,
    CASE (RANDOM() * 5)::INT
      WHEN 0 THEN 'San Francisco, CA'
      WHEN 1 THEN 'New York, NY'
      WHEN 2 THEN 'Austin, TX'
      WHEN 3 THEN 'Remote'
      ELSE NULL
    END AS job_location
  FROM date_range WHERE RANDOM() < 0.15  -- sample to ~550 rows
)
SELECT * FROM generated;
```

## Notes

- **Null blindness:** Most pipelines are tested only on "happy path" data. Always include NULL, empty string, and tri-state (TRUE/FALSE/NULL) variants in fixtures.
- **Distribution matters:** Synthetic data must reflect real cardinality skew. If 80% of your jobs are remote in production, your test data should mirror this, or aggregations will lie.
- **Idempotency testing:** Fixtures are essential for proving your pipeline is idempotent—run it twice on the same data, get the same result. Synthetic data lets you test at scale.
- **Connects to:** Data contracts (schema + distribution guarantees), profiling (understanding what "normal" looks like), and observability (alerting when real data violates test assumptions).
- **Revisit when:** Adding new transformations, changing schemas, or onboarding new dimensions. Stale test data is almost worse than none—it creates false confidence.
