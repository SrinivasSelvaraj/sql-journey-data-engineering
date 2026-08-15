---
date: 2026-08-15
phase: streaming
topic: Spark: RDDs, DataFrames and the Catalyst optimiser
---

# Spark: RDDs, DataFrames and the Catalyst optimiser

*Streaming and distributed processing*

## Concept

RDDs (Resilient Distributed Datasets) are Spark's lowest-level abstraction—immutable collections partitioned across a cluster that can recover from node failures. DataFrames layer SQL semantics and columnar structure on top of RDDs, organizing data into named columns with inferred or explicit schemas. The Catalyst optimizer sits between you and execution: it parses your DataFrame/SQL queries into an unoptimized logical plan, applies rule-based transformations (predicate pushdown, constant folding, join reordering), and generates an optimized physical plan before bytecode compilation.

This matters intensely in streaming because data never arrives complete or sorted. Without Catalyst, you'd hand-tune partition strategies, join ordering, and filter placement for every query—work that breaks the moment upstream data characteristics change. With Catalyst, you write declarative logic once; the optimizer adapts to schema, cardinality, and data distribution, critical when micro-batches vary wildly in size or when late-arriving records reshape join windows.

Breaks without it: naive RDD operations cause full-dataset shuffles on every transformation; unoptimized joins on streaming windows explode memory; filters applied *after* reads scan entire partitions instead of pruning at source. In a 24/7 pipeline, this translates to cascading backpressure, OOM failures, and query drift as data skew evolves.

## Practice

**Problem:** You're ingesting job postings in real time. For each micro-batch, find all remote-eligible jobs posted in the last 24 hours with salary ≥ $100k, grouped by abbreviated title, and return the count and average salary. Without Catalyst optimization, filters would apply after reading all columns; with it, predicates push down to the source, and grouping aggregations are planned efficiently.

```sql
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND salary_year_avg >= 100000
  AND job_posted_date >= DATE_SUB(CURRENT_DATE, 1)
GROUP BY job_title_short
ORDER BY posting_count DESC;
```

In Spark DataFrame API, this same query benefits from Catalyst's predicate pushdown: the `job_work_from_home`, `salary_year_avg`, and `job_posted_date` filters are pushed into the read plan, reducing I/O before aggregation. The optimizer also recognizes that `job_title_short` cardinality is low relative to salary computation, so it may pre-aggregate per partition before the final shuffle.

## Notes

- **RDD→DataFrame mistake:** Calling `.rdd` to escape DataFrame APIs defeats optimization; if you're tempted, you've likely hit a gap in Catalyst's rule set—file an issue or restructure the query.
- **Streaming-specific gotcha:** Catalyst optimizes each micro-batch in isolation; if your streaming join involves a 24-hour window on out-of-order data, late arrivals won't retrigger optimization—plan state retention accordingly.
- **Catalyst's blind spots:** Complex nested structures, UDFs (especially non-Pandas ones), and non-pushable predicates (e.g., subqueries in WHERE) bypass optimization; use `explain()` to inspect the physical plan and refactor UDFs into SQL where possible.
- **Adjacent topic:** Tungsten (Spark's memory management layer) works in concert with Catalyst—optimization determines the physical layout; Tungsten executes it efficiently in off-heap memory.
- **Revisit:** Use `df.explain(mode='extended')` to visualize logical and physical plans; understanding SCAN vs. FILTER vs. EXCHANGE operators is essential for debugging pipeline bottlenecks in production streaming.
