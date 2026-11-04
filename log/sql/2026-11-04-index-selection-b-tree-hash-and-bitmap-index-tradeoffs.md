---
date: 2026-11-04
phase: sql
topic: Index selection: B-tree, hash and bitmap index tradeoffs
---

# Index selection: B-tree, hash and bitmap index tradeoffs

*SQL for analytics and engineering*

## Concept

Index selection determines query performance by influencing how the database retrieves rows. B-tree indexes (the default) work well for range queries and sorted access because they maintain order; they're ideal for `WHERE salary > 100000` or `ORDER BY job_posted_date`. Hash indexes are faster for exact equality matches (`WHERE job_id = 42`) but useless for ranges or sorting—the database must scan them linearly for `>` or `<`. Bitmap indexes are specialized for low-cardinality columns (few distinct values, like `job_work_from_home` with only TRUE/FALSE); they compress efficiently and excel at filtering `WHERE job_work_from_home = true AND job_location = 'Remote'`, but they bloat on high-cardinality columns like `job_id`.

The wrong index choice causes full table scans. If you index `job_posted_date` with a hash index but query `WHERE job_posted_date >= '2024-01-01'`, the database cannot use it and scans all rows. Similarly, a bitmap index on `job_title_short` (thousands of distinct values) wastes space and slows writes. Understanding your query patterns—do you filter on ranges, exact matches, or combinations of low-cardinality columns?—is essential before creating an index.

## Practice

**Problem:** You have 2 million rows in `job_postings_fact`. Users frequently:
1. Search for remote jobs posted in the last 90 days with salary > 120k
2. Look up a specific job by ID
3. Filter by work-from-home status and location together

Design indexes to support these queries efficiently.

```sql
-- Index 1: B-tree composite for range + equality (query 1)
-- Supports: job_posted_date >= X AND salary_year_avg > Y (range on posted_date, then salary)
CREATE INDEX idx_posted_salary ON job_postings_fact(job_posted_date DESC, salary_year_avg DESC);

-- Index 2: Hash or B-tree for exact lookup (query 2)
-- Fast equality match; B-tree chosen for flexibility if future queries add ranges
CREATE INDEX idx_job_id ON job_postings_fact(job_id);

-- Index 3: Bitmap for low-cardinality columns (query 3)
-- Boolean + location (assume ~50 distinct locations); efficient AND filters
CREATE BITMAP INDEX idx_wfh_location ON job_postings_fact(job_work_from_home, job_location);

-- Query 1: Benefits from idx_posted_salary (B-tree preserves order)
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  AND salary_year_avg > 120000
  AND job_work_from_home = true
ORDER BY job_posted_date DESC;

-- Query 2: Uses idx_job_id (hash or B-tree both fast for =)
SELECT * FROM job_postings_fact WHERE job_id = 5432;

-- Query 3: Uses bitmap index for two low-cardinality columns
SELECT COUNT(*) FROM job_postings_fact
WHERE job_work_from_home = true AND job_location = 'Remote';
```

## Notes

- **Composite index order matters**: In a B-tree, lead with columns used in range predicates (`job_posted_date` before `salary_year_avg`). The database uses the first column for seeks, then subsequent columns for filtering.
- **Bitmap indexes are database-specific**: Oracle and some others support them natively; PostgreSQL uses BRIN for similar effects on low-cardinality sorted columns. Always check your engine's documentation.
- **Index bloat degrades writes**: Every INSERT/UPDATE/DELETE must maintain all indexes. Five indexes on a write-heavy table can become a bottleneck. Monitor index fragmentation and drop unused ones.
- **Query plans are your truth**: Use `EXPLAIN` or `EXPLAIN ANALYZE` to verify the optimizer actually *uses* your index. A composite index on (A, B) won't help a query filtering only on B; you may need separate indexes.
- **Cardinality estimation**: Low cardinality (<100 distinct values) favors bitmap; high cardinality (millions of unique values) needs B-tree. `job_title_short` with 10k+ titles should use B-tree, not bitmap.
