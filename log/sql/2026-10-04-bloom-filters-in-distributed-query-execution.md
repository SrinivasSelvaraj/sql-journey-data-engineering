---
date: 2026-10-04
phase: sql
topic: Bloom filters in distributed query execution
---

# Bloom filters in distributed query execution

*SQL for analytics and engineering*

## Concept

A Bloom filter is a probabilistic data structure that answers "is this element in the set?" with zero false negatives but possible false positives. In distributed query execution, coordinators use Bloom filters to prune partitions or remote workers before sending expensive broadcast joins or fetches. When a join probe references a large dimension table, the executor builds a Bloom filter from the inner side and pushes it to scan operators on the outer side—only rows whose join keys *might* exist in the inner set pass the filter, eliminating network round-trips and I/O for impossible matches.

Without Bloom filter pushdown, a distributed join sends every outer row to the join operator, even if its join key has no match. This causes unnecessary network traffic, memory pressure on the join node, and wasted CPU. In analytics on cloud storage (S3, GCS), it also triggers redundant object fetches. Modern SQL engines (Presto, Spark, BigQuery) apply Bloom filters automatically on broadcast joins and dynamic partition elimination; understanding when they activate helps you reason about query plan costs and identify bottlenecks where filters aren't being pushed.

The filter trades small memory overhead (typically 1–2% of inner cardinality) and CPU cycles during build/probe for dramatic I/O and network savings. False positives are acceptable—the join operator itself confirms matches—so the false positive rate can be tuned to memory budget. Bloom filters fail to help if the outer table is small, the join selectivity is already high, or the filter cannot be serialized to remote workers in time.

## Practice

**Problem:** You have a fact table of 500M job postings and want to join it to a dimension table of 50K valid job_title_short values (filtered by recent hiring trends). Without a Bloom filter pushdown, the scan of job_postings_fact sends all 500M rows across the network to the join operator. Write a query that makes the join pushdown-friendly and explain how the engine should apply the filter.

```sql
SELECT 
  f.job_id,
  f.job_title_short,
  f.salary_year_avg,
  d.trend_score
FROM job_postings_fact f
INNER JOIN (
  SELECT job_title_short, trend_score
  FROM trending_job_titles
  WHERE trend_score > 0.8
) d ON f.job_title_short = d.job_title_short
WHERE f.job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
```

**Execution:** The optimizer builds a Bloom filter from the 50K trending_job_titles rows (join key = job_title_short) and pushes it into the scan of job_postings_fact. Before emitting rows, the scan tests each job_title_short against the filter; ~99.8% of non-matching titles are rejected locally, and only ~50K rows (plus false positives) traverse the network to the join operator. Network and join memory costs drop by orders of magnitude.

## Notes

- **Bloom filter size vs. false positive rate:** Larger filters (more bits per element) reduce false positives but use more memory; modern engines choose 10–20 bits/element by default. Too aggressive and you waste memory; too conservative and false positives hurt.
- **Join order and broadcastability:** Filters only help when the small side is broadcast and filters reach the large side's scan operator. Rewrite subqueries to ensure the dimension table is clearly small (explicit `LIMIT` or aggregate, or cardinality statistics).
- **When pushdown fails:** If the join key is computed (e.g., `LOWER(job_title_short)`), the filter may not serialize or match; keep join predicates simple and direct to column references.
- **Adjacent topics:** Dynamic partition pruning (filters on partition columns), adaptive query execution (runtime feedback to adjust filter aggressiveness), and hash semi-joins (alternative to Bloom when memory is tight).
- **Revisit:** Understand your engine's query plan output (Spark's `ExecutedPlan`, Presto's `EXPLAIN ANALYZE`) to confirm Bloom filters are being pushed; if missing, check subquery complexity, join key complexity, or cardinality estimates.
