---
date: 2026-11-04
phase: reliability
topic: Continuous integration: automated testing on pull requests
---

# Continuous integration: automated testing on pull requests

*Quality, reliability and the professional layer*

## Concept

Continuous integration (CI) automatically runs tests—data validation, schema checks, transformation logic—whenever code is pushed to a pull request. Before CI, broken logic merged silently into production. With it, you catch regressions before they propagate downstream.

In data engineering, CI testing verifies that SQL transformations produce expected schemas and row counts, that new columns don't break existing logic, and that data quality thresholds hold. A missing NOT NULL constraint, a silent join that doubles rows, or a timestamp column that suddenly contains nulls—these slip past code review without automated checks.

Without CI, you own failures reactively. With it, you own quality proactively. The difference between "I pushed code" and "I'm responsible for what runs" is automation that forced you to think about failure modes before they became incidents.

## Practice

**Problem:** Your team added a new column `job_posting_source` to `job_postings_fact`, but legacy jobs without this field now fail downstream transformations. You need a CI test to catch NULL values in critical columns before merge.

```sql
-- CI test: validate no nulls in required columns on new data
SELECT 
  COUNT(*) as null_count
FROM job_postings_fact
WHERE 
  job_id IS NULL
  OR job_title_short IS NULL
  OR job_posted_date IS NULL
  OR job_location IS NULL;
-- Assert: null_count = 0, else fail PR
```

**Alternative test for row count consistency:**
```sql
-- Verify no unexpected row duplication from new join logic
SELECT 
  job_id, 
  COUNT(*) as row_count
FROM job_postings_fact
GROUP BY job_id
HAVING COUNT(*) > 1;
-- Assert: returns 0 rows, else fail PR
```

## Notes

- **Test timing matters:** Run tests against staging data or a sample subset—full table scans on every PR are expensive and slow feedback loops.
- **Schema drift is silent:** Use `EXCEPT` or `EXCEPT ALL` queries to detect unexpected column additions or removals before they break downstream code.
- **Connect to data contracts:** CI enforces contracts you wrote down (e.g., "salary_year_avg must be NOT NULL and >= 0"). Without contracts, tests are arbitrary.
- **False negatives are toxic:** A test that passes on bad data is worse than no test. Validate your test fails when it should; run the PR branch locally first.
- **Adjacent: automated linting, orchestration monitoring, and incident post-mortems.** CI is the first line; observability in production is the last.
