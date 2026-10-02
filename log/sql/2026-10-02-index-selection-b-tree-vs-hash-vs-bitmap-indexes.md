---
date: 2026-10-02
phase: sql
topic: Index selection: B-tree vs hash vs bitmap indexes
---

# Index selection: B-tree vs hash vs bitmap indexes

*SQL for analytics and engineering*

## Concept

B-tree indexes are the default choice for range queries and sorted access. They maintain sorted order, making them ideal for `WHERE salary > 100000`, `ORDER BY job_posted_date`, and inequality filters. B-trees scale logarithmically and support both exact-match and range predicates efficiently. Use them when your query filters on continuous numeric columns, dates, or strings where ordering matters.

Hash indexes excel at exact equality lookups only (`WHERE job_id = 42`). They distribute values into buckets via hash function, delivering O(1) average-case lookup. They're faster than B-trees for simple equality but useless for ranges—a query like `WHERE salary BETWEEN 80000 AND 120000` will force a full scan. Hash indexes also don't support `ORDER BY`.

Bitmap indexes pack many low-cardinality Boolean or categorical values efficiently. `job_work_from_home BOOLEAN` is an ideal candidate: each distinct value gets one bitmap (true/false = 2 bitmaps), and bitwise AND/OR operations answer multi-dimensional filters in milliseconds. They're common in data warehouses but rare in OLTP systems. Avoid bitmap indexes on high-cardinality columns like `job_id`—the bitmap becomes as large as a B-tree with worse performance.

## Practice

**Problem:** You're analyzing job postings. Queries frequently filter by salary range, filter by remote status, order results by posting date, and sometimes combine all three. Which index strategy minimizes query time?

```sql
-- Query pattern: salary range + remote filter + order by date
SELECT job_id, job_title_short, salary_year_avg, job_posted_date
FROM job_postings_fact
WHERE salary_year_avg BETWEEN 80000 AND 150000
  AND job_work_from_home = true
ORDER BY job_posted_date DESC;

-- Index strategy:
CREATE INDEX idx_salary_date ON job_postings_fact(salary_year_avg, job_posted_date DESC);
CREATE BITMAP INDEX idx_remote ON job_postings_fact(job_work_from_home);

-- Why: B-tree on (salary, date) handles the range filter and sort in one pass.
-- Bitmap on remote status lets the optimizer quickly identify the true subset,
-- then intersect with the salary range result.
```

## Notes

- **B-tree for ranges, hash for equality only.** Hash indexes silently degrade to full scans on `>`, `<`, `BETWEEN`—no error, just slow queries. Never reach for hash unless your WHERE clause is purely `=`.

- **Cardinality matters for bitmaps.** If `job_work_from_home` has only 2 values, a bitmap is 1000× smaller than a B-tree. If a column has 1M distinct values, bitmap indexes blow up; use B-tree instead.

- **Composite indexes preserve sort order.** `CREATE INDEX idx_salary_date ON (salary_year_avg, job_posted_date)` lets a single index satisfy both a range filter and an ORDER BY—check EXPLAIN PLAN for "index skip scan" or "index range + order" proof.

- **Bitmap indexes are query-time tools, not write-time.** They excel in read-heavy analytics. Bitmap maintenance on frequent inserts/updates can hurt throughput; use them in data warehouses, not live transactional systems.

- **Index selection is query-plan-specific.** Always EXPLAIN; cardinality estimates and selectivity drive the optimizer's choice. An index on a 99%-true column may not be chosen because full scan is cheaper. Revisit after schema changes or data skew.
