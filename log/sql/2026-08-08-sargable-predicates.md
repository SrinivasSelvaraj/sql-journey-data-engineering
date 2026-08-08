---
date: 2026-08-08
phase: sql
topic: Sargable predicates
---

# Sargable predicates

*SQL for analytics and engineering*

## Concept

A **sargable predicate** is a WHERE clause condition that allows the database query optimizer to use an index to narrow the result set before retrieving rows. "Sargable" stands for "search argument able." The predicate must reference a column directly without transformation—the optimizer can then seek into an index on that column rather than scanning the entire table.

Sargability matters enormously in interview settings because it separates performant queries from ones that work but crawl at scale. A non-sargable predicate forces a full table scan, examining every single row before filtering. This becomes catastrophic on tables with millions or billions of rows. Common culprits: wrapping a column in a function (`WHERE YEAR(date_col) = 2024`), using `NOT IN` with subqueries, or arithmetic operations (`WHERE salary * 1.1 > 100000`).

Without sargable predicates, you lose index usage. The query plan shows a scan instead of a seek, execution time balloons, and you've failed the performance part of the interview. Learning to spot and rewrite these is a core engineering skill.

## Practice

**Problem:** Write a query to find all remote data engineer jobs posted in 2024 with average salary over $120k. The naive approach uses non-sargable predicates.

```sql
-- ❌ Non-sargable: YEAR() function prevents index seek on job_posted_date
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE YEAR(job_posted_date) = 2024
  AND job_work_from_home = TRUE
  AND salary_year_avg > 120000
  AND job_title_short LIKE '%Data Engineer%';

-- ✅ Sargable: Column references only, range comparison, equality on booleans
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
  AND job_posted_date < '2025-01-01'
  AND job_work_from_home = TRUE
  AND salary_year_avg > 120000
  AND job_title_short LIKE 'Data Engineer%';
```

The second version allows the optimizer to seek indexes on `job_posted_date`, `job_work_from_home`, and `salary_year_avg` in sequence, dramatically reducing rows examined.

## Notes

- **Function wrapping kills indexes:** `WHERE UPPER(col) = 'VALUE'`, `WHERE DATE(timestamp_col) = today()`, `WHERE SUBSTRING(col, 1, 3) = 'ABC'` all force scans. Rewrite as range comparisons or computed columns.
- **LIKE with leading wildcards is non-sargable:** `LIKE '%text'` requires scanning; `LIKE 'text%'` can use an index.
- **Connects to query plans:** Always check `EXPLAIN PLAN` output for "Seq Scan" vs. "Index Seek/Scan." This is your feedback loop in interviews.
- **Trade-off with readability:** Sometimes the most readable query (e.g., `CAST(salary AS FLOAT) / 1000 > 120`) is not sargable. Understand the trade and decide consciously.
- **Revisit: index design, materialized views, and predicate pushdown** in distributed systems—sargability principles cascade through the entire stack.
