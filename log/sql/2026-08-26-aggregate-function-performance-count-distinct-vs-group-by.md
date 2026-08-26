---
date: 2026-08-26
phase: sql
topic: Aggregate function performance: COUNT(DISTINCT) vs GROUP BY
---

# Aggregate function performance: COUNT(DISTINCT) vs GROUP BY

*SQL for analytics and engineering*

## Concept

`COUNT(DISTINCT column)` is a convenient one-liner that counts unique values in a single pass, but it forces the database to materialize all distinct values in memory before counting—making it expensive on high-cardinality columns or large result sets. `GROUP BY`, by contrast, distributes the work across a hash or sort aggregation plan, often with better memory efficiency and the ability to push predicates earlier in the execution tree.

The performance gap widens dramatically when:
- The column has high cardinality (millions of unique values) and memory-constrained execution
- You need to filter or join before aggregation—`GROUP BY` lets the optimizer push those operations down
- You're counting distinct combinations of multiple columns—`COUNT(DISTINCT col1, col2, ...)` becomes a single expensive operation, whereas `GROUP BY col1, col2` distributes the cost

Without understanding this distinction, you risk writing queries that appear correct but timeout on production datasets, or missing opportunities to add WHERE clauses that would prune billions of rows before the aggregation even begins.

## Practice

**Problem:** Find the number of distinct job locations where remote work is available, and the count of distinct job titles for each. Return location and both counts.

```sql
-- Inefficient: two COUNT(DISTINCT) calls
SELECT 
  job_location,
  COUNT(DISTINCT job_title_short) as unique_titles,
  COUNT(DISTINCT job_id) as job_count
FROM job_postings_fact
WHERE job_work_from_home = true
GROUP BY job_location;

-- Better: move GROUP BY to subquery to separate concerns
SELECT 
  job_location,
  COUNT(DISTINCT job_title_short) as unique_titles,
  COUNT(*) as job_count
FROM job_postings_fact
WHERE job_work_from_home = true
GROUP BY job_location;

-- Most efficient: pre-aggregate if cardinality is extreme
WITH filtered AS (
  SELECT job_location, job_title_short, job_id
  FROM job_postings_fact
  WHERE job_work_from_home = true
)
SELECT 
  job_location,
  COUNT(DISTINCT job_title_short) as unique_titles,
  COUNT(DISTINCT job_id) as job_count
FROM filtered
GROUP BY job_location;
```

## Notes

- **COUNT(DISTINCT) + multiple columns:** Most databases don't support `COUNT(DISTINCT col1, col2)` syntax cleanly; use `COUNT(DISTINCT CONCAT(col1, col2))` or window functions instead—this is another reason `GROUP BY` often wins architecturally.
- **Index leverage:** `GROUP BY` can exploit indexes on the grouped column; `COUNT(DISTINCT)` often must scan the entire table, defeating index benefits.
- **Approximate counting:** For massive cardinality (HyperLogLog, sketches), know when exact `COUNT(DISTINCT)` is unnecessary—approximate algorithms can be 100× faster.
- **EXPLAIN PLAN reading:** Always run `EXPLAIN` on both approaches; look for "Hash Aggregate" (GROUP BY) vs. "Aggregate" (COUNT DISTINCT)—the former usually shows lower estimated cost.
- **Revisit:** Materialized views and incremental aggregation; window functions (`ROW_NUMBER() OVER (PARTITION BY...)`) as an alternative to GROUP BY; DISTINCT itself as a performance anti-pattern.
