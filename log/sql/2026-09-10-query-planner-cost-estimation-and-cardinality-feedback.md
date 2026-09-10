---
date: 2026-09-10
phase: sql
topic: Query planner cost estimation and cardinality feedback
---

# Query planner cost estimation and cardinality feedback

*SQL for analytics and engineering*

## Concept

The query planner estimates how many rows will flow through each step of your query plan (cardinality), then uses those estimates to choose between sequential scan, index scan, hash join, nested loop join, and sort algorithms. When cardinality estimates are accurate, the planner picks the optimal plan. When they're wildly wrong—often due to stale statistics, complex predicates the planner can't reason about, or data skew—the planner may choose a plan that's orders of magnitude slower (e.g., nested loop when hash join is needed, or vice versa).

Cardinality feedback matters most in analytics and batch ETL where a single slow query can block pipelines, and where you may not notice misestimates on small dev datasets that blow up on production. Without good estimates, you get full table scans when index scans would help, or expensive nested loops on large fact tables. You diagnose this by reading EXPLAIN output: look for "rows=X" estimates versus actual rows, and for plan shape surprises (e.g., sudden nested loop on a multi-million row table).

The fix is usually: run ANALYZE to refresh table statistics, add LIMIT hints to tighten selectivity bounds, rewrite complex WHERE clauses to be more planner-friendly, or use manual index hints when the planner is provably wrong.

## Practice

**Problem:** You're querying job postings. Management wants all US-based remote jobs posted in 2024 with salary > $120k. You write the query and it runs in 3 seconds; your colleague runs the same query on production (10× larger dataset) and it hangs. Inspect the plan and fix it.

```sql
-- Original query (slow on large data)
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_location LIKE '%United States%'
  AND job_work_from_home = true
  AND salary_year_avg > 120000
  AND EXTRACT(YEAR FROM job_posted_date) = 2024;

-- EXPLAIN shows: Seq Scan with Filter, rows estimate wildly off
-- Problem: LIKE and EXTRACT prevent statistics-driven filtering

-- Solution: rewrite for planner clarity and add index
CREATE INDEX idx_job_remote_salary_date ON job_postings_fact
  (job_work_from_home, salary_year_avg, job_posted_date)
  WHERE job_location LIKE '%United States%';

-- Refactored query (planner-friendly)
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE job_location LIKE '%United States%'
  AND job_work_from_home = true
  AND salary_year_avg > 120000
  AND job_posted_date >= '2024-01-01'
  AND job_posted_date < '2025-01-01';

-- Run ANALYZE to refresh statistics
ANALYZE job_postings_fact;
```

## Notes

- **Stale stats kill plans:** Always ANALYZE after bulk inserts or schema changes; many teams set this on a daily/weekly schedule.
- **LIKE and EXTRACT are opaque:** Planners can't estimate selectivity of `LIKE '%text%'` or `EXTRACT(YEAR FROM date) = X`; use range predicates (`date >= ... AND date < ...`) instead.
- **Data skew makes estimates meaningless:** If 90% of rows have `job_work_from_home = false`, a nested loop on the true subset might still be optimal despite high cardinality estimate for the join.
- **Connects to index strategy:** Cardinality estimates drive index selection; a partial index on filtered rows (e.g., `WHERE job_work_from_home = true`) can give the planner sharper estimates and reduce bloat.
- **Revisit with EXPLAIN ANALYZE:** Run `EXPLAIN ANALYZE` (not just `EXPLAIN`) in production to compare predicted vs. actual rows; gaps > 10× warrant investigation.
