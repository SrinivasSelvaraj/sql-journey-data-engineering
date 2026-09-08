---
date: 2026-09-08
phase: streaming
topic: Stateless transformations: map, filter and flatMap
---

# Stateless transformations: map, filter and flatMap

*Streaming and distributed processing*

## Concept

Stateless transformations operate on individual records without maintaining memory of previous records—each input produces an output independently. The three primitives serve distinct purposes: **map** transforms each record's structure or values; **filter** removes records that don't meet criteria; **flatMap** expands one record into zero or many records. In streaming contexts, stateless transformations are critical because they require no distributed state management, making them horizontally scalable and fault-tolerant. Without them, you'd be forced to buffer or aggregate data, introducing latency and complexity.

What breaks without proper stateless transformation design: unbounded memory growth (if you try to aggregate without explicit windowing), late arrivals causing incorrect results (because you assumed ordered data), and cascading failures across partitions (because state becomes a bottleneck). The key insight is recognizing when a problem truly *requires* state—counting, deduplication, joins—versus when it's just filtering or reshaping records.

## Practice

**Problem:** You have job postings arriving in a stream. Extract only remote, high-paying roles (>$120k), then split each posting into one record per word in the job title for downstream keyword analysis.

```sql
-- Using Spark Structured Streaming pattern (SQL-equivalent thinking)
SELECT 
  job_id,
  EXPLODE(SPLIT(job_title_short, ' ')) AS title_word,
  salary_year_avg,
  job_posted_date
FROM job_postings_fact
WHERE job_work_from_home = TRUE 
  AND salary_year_avg > 120000
```

This chains: **filter** (WHERE clause) removes non-remote and low-salary rows → **flatMap** (EXPLODE + SPLIT) expands one job title into multiple keyword rows. In a true streaming engine (Flink, Spark Streaming), you'd apply these operations on micro-batches or events as they arrive, never holding state.

## Notes

- **Partition preservation matters:** stateless ops maintain parallelism across partition boundaries, but a poor partitioning key upstream will cause skew downstream—don't assume distribution is automatic.
- **Explode/flatMap pitfall:** generating too many records per input (e.g., splitting on every character instead of words) kills throughput; always validate cardinality assumptions before deploying.
- **Lazy evaluation:** in Spark, map/filter/flatMap are lazy—nothing executes until an action is called; this is efficient but can hide bugs in logic until runtime.
- **Connects to:** stateful operations (aggregations, joins, deduplication) are built on top of stateless ones; windowing also relies on filtering and mapping to prepare data for stateful computation.
- **Revisit:** understanding *when* to use flatMap vs. nested unnest() operations; the performance difference varies by engine and can be significant at scale.
