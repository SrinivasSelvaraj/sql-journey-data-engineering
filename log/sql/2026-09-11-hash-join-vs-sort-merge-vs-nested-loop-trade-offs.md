---
date: 2026-09-11
phase: sql
topic: Hash join vs sort merge vs nested loop trade-offs
---

# Hash join vs sort merge vs nested loop trade-offs

*SQL for analytics and engineering*

## Concept

A join operation is often the most expensive part of a query, and the database optimizer chooses one of three strategies based on data size, indexes, and sort order. **Hash join** builds an in-memory hash table from the smaller (build) table, then probes it with rows from the larger (probe) table—fast O(n+m) when both tables fit in memory, but fails catastrophically if memory is exhausted. **Sort-merge join** sorts both tables on the join key and walks through them in parallel—O(n log n + m log m) but useful when data is already sorted or when one table is too large for a hash table. **Nested loop join** compares every row from the outer table against every row from the inner table—O(n×m)—and is only acceptable for small result sets or when indexes exist on the join column of the inner table.

The choice matters enormously in production. A hash join on a 100M-row fact table will OOM if the build table doesn't fit in the work_mem or hash_work_mem budget; the query either fails or spills to disk (becoming nested loop speed). A sort-merge join can leverage existing indexes and pre-sorted data from a previous operation. A nested loop without an index on the inner join column turns a millisecond query into minutes. Most modern optimizers (Postgres, BigQuery, Snowflake) default to hash join when safe, but you must reason about memory, cardinality, and index availability to predict what the plan will actually do.

## Practice

**Problem:** Find the job titles and average salary for each job title that have at least 50 postings and where the average salary exceeds $100k. Then join this result to the raw job_postings_fact table to count how many of those qualifying jobs are remote-eligible.

```sql
WITH job_summary AS (
  SELECT 
    job_title_short,
    COUNT(*) AS posting_count,
    AVG(salary_year_avg) AS avg_salary
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
  GROUP BY job_title_short
  HAVING COUNT(*) >= 50
    AND AVG(salary_year_avg) > 100000
)
SELECT 
  js.job_title_short,
  js.avg_salary,
  COUNT(*) AS total_postings,
  SUM(CASE WHEN jpf.job_work_from_home THEN 1 ELSE 0 END) AS remote_count
FROM job_summary js
INNER JOIN job_postings_fact jpf
  ON js.job_title_short = jpf.job_title_short
GROUP BY js.job_title_short, js.avg_salary
ORDER BY js.avg_salary DESC;
```

The CTE aggregates first (reducing cardinality dramatically), making the subsequent hash join on job_title_short cheap and predictable. Without the CTE, you'd join full tables first, then aggregate—much slower and more memory pressure.

## Notes

- **Hash join spill**: If the build table's hash table exceeds available memory, the database spills to disk. Monitor work_mem / hash_work_mem; a 5GB build table on a 4GB budget becomes 100× slower. Use `EXPLAIN ANALYZE` to spot spills.
- **Index-backed nested loop**: A nested loop with a B-tree index on the inner table's join column can be faster than hash join for small outer tables (< 1000 rows). The optimizer uses this when it sees low cardinality.
- **Pre-sorted data matters**: If both tables are already sorted on the join key (e.g., data from a previous sort or a clustered index), sort-merge can avoid re-sorting. Check `EXPLAIN` output for "Sort" nodes that could be eliminated.
- **Join order is not commutative in cost**: The optimizer reorders joins to reduce cardinality early. Always filter aggressively before joins; move WHERE clauses into CTEs or subqueries to reduce the build table size first.
- **Related**: Query plan analysis (EXPLAIN), cardinality estimation bugs, and partition pruning in distributed joins (Snowflake's table pruning, BigQuery's dynamic partition elimination) all depend on understanding which join strategy is chosen.
