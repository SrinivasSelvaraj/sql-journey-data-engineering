---
date: 2026-08-26
phase: sql
topic: Generated columns and computed column indexing
---

# Generated columns and computed column indexing

*SQL for analytics and engineering*

## Concept

Generated columns (also called computed or virtual columns) are columns whose values are derived from expressions involving other columns, rather than stored independently. They are useful when you frequently need the same calculation—for example, converting salary to monthly rates, extracting year from a date, or normalizing location strings. Most modern databases (PostgreSQL 12+, MySQL 5.7+, SQL Server) support them, though syntax and persistence vary: some store the computed value (stored generated columns), others calculate on retrieval (virtual generated columns).

Indexing a generated column is powerful for query performance. If you frequently filter or join on `salary_month = salary_year_avg / 12`, creating an index on that generated column lets the query planner use it directly instead of computing the expression for every row during a scan. Without the index, the database must evaluate the expression at runtime, defeating the optimization opportunity.

The trade-off is write performance and storage: generated columns consume extra space and CPU on insert/update operations. They also reduce schema flexibility—changing the expression requires altering the column definition. Use them judiciously: prioritize high-read, low-write tables and expressions that appear in WHERE clauses, JOIN conditions, or GROUP BY operations frequently enough to justify the cost.

## Practice

**Problem:** You need to query job postings where the monthly salary is above $8,000 and jobs were posted in 2024. Currently, queries recalculate monthly salary on every scan. Show how to add an indexed generated column and write an efficient query.

```sql
-- Add indexed generated column
ALTER TABLE job_postings_fact
ADD COLUMN salary_month_avg DECIMAL(10, 2) GENERATED ALWAYS AS (salary_year_avg / 12) STORED;

CREATE INDEX idx_salary_month_posted_date 
ON job_postings_fact(salary_month_avg, YEAR(job_posted_date));

-- Efficient query using the generated column
SELECT job_id, job_title_short, salary_year_avg, salary_month_avg, job_posted_date
FROM job_postings_fact
WHERE salary_month_avg > 8000
  AND YEAR(job_posted_date) = 2024
ORDER BY salary_month_avg DESC;
```

## Notes

- **Common mistake:** Creating a generated column without indexing it; the expression still evaluates at runtime, wasting storage with no read benefit.
- **Syntax varies:** PostgreSQL uses `GENERATED ALWAYS AS (expr) STORED`; MySQL defaults to virtual; SQL Server requires `PERSISTED` for indexability. Always check your dialect.
- **Index design matters:** If filtering by both the generated column and another column (like date), consider a composite index on both; single-column indexes on the generated column alone may not help multi-predicate queries.
- **Adjacent topics:** Query plan analysis (EXPLAIN) to verify index usage, statistics maintenance on generated columns, and cost-benefit analysis of denormalization vs. on-the-fly calculation.
- **Revisit:** Test with real workload patterns—measure both write latency and query speedup before committing to storage-based generation in production.
