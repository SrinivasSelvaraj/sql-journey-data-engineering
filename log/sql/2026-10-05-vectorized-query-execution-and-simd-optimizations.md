---
date: 2026-10-05
phase: sql
topic: Vectorized query execution and SIMD optimizations
---

# Vectorized query execution and SIMD optimizations

*SQL for analytics and engineering*

## Concept

Vectorized query execution processes multiple rows in a single CPU instruction cycle, leveraging SIMD (Single Instruction Multiple Data) hardware capabilities rather than executing row-by-row. Modern analytic databases like DuckDB, Clickhouse, and newer Postgres versions use columnar storage and vectorized operators to push computation into CPU cache and vector registers, reducing memory bandwidth requirements and instruction overhead. This is particularly critical for analytics workloads where you're filtering, aggregating, or scanning millions of rows—a vectorized scan can be 5–10× faster than row-at-a-time execution because it amortizes loop overhead and maximizes cache locality.

Without vectorization, the query engine fetches one row, evaluates predicates, and moves to the next—thrashing the CPU pipeline with branch mispredictions and memory stalls. This matters most when you have selective filters (WHERE clauses that eliminate 90% of rows) or wide scans with simple aggregations; narrow, selective queries on few columns benefit hugely from vector processing. Modern engines use *batching*—processing 1024–4096 rows at once through the same code path—so your SQL doesn't change, but execution plans differ fundamentally between row-store and vectorized engines.

## Practice

**Problem:** You're analyzing job postings and need to find the count of remote positions with average salary > $100k, grouped by job title. The dataset has 500k rows. Write a query that will execute efficiently on a vectorized engine, and reason about what would slow a row-at-a-time executor.

```sql
SELECT
  job_title_short,
  COUNT(*) AS position_count,
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = true
  AND salary_year_avg > 100000
  AND job_posted_date >= CURRENT_DATE - INTERVAL 12 MONTH
GROUP BY job_title_short
HAVING COUNT(*) > 5
ORDER BY avg_salary DESC;
```

**Why this executes well on vectorized engines:** The WHERE predicates are selective and column-oriented (boolean and numeric comparisons on isolated columns), allowing the vectorizer to apply all three filters in a single pass over 4k-row batches without materializing intermediate results. The GROUP BY aggregation then operates only on filtered batches, keeping working sets in L2 cache. A row-at-a-time engine would evaluate all three predicates per row, incur branch mispredictions on each conditional, and likely spill intermediate grouping data to memory.

## Notes

- **Column pruning matters:** Only `job_title_short`, `salary_year_avg`, and `job_work_from_home` are needed; vectorized engines skip reading other columns entirely. Row-stores often read full rows regardless.
- **Predicate pushdown and selectivity order:** Place most selective filters first (e.g., boolean check before numeric range) in your mental model—though optimizers reorder these; understanding selectivity helps predict which engine will struggle.
- **Batch size trade-offs:** Larger batches increase cache pressure but reduce loop overhead; typical sweet spot is 1024–8192 rows. This is engine-tuned, not SQL-tunable, but explains why DuckDB often outperforms Postgres on analytics.
- **Aggregation strategy:** Vectorized engines use *streaming aggregation* (partial aggregates per batch) or *hash aggregation* differently than row-stores; GROUP BY performance is more predictable and scales better with vectorization.
- **Adjacent concepts to deepen:** Query plan analysis (EXPLAIN output differs between engines), column-store compression (RLE, dictionary encoding pair with vectorization), and partition pruning (complementary optimization at file/block level).
