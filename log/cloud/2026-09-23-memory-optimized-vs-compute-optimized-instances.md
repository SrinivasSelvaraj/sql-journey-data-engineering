---
date: 2026-09-23
phase: cloud
topic: Memory-optimized vs compute-optimized instances
---

# Memory-optimized vs compute-optimized instances

*Cloud platforms and storage*

## Concept

Memory-optimized instances (r-series, x-series) prioritize high RAM-to-CPU ratio and are ideal for workloads that hold entire datasets in memory, perform complex aggregations, or need fast random access patterns. Compute-optimized instances (c-series) maximize CPU cores relative to memory and suit workloads dominated by sequential processing, transformations, or heavy algorithmic work. The choice directly impacts query cost and latency: a query scanning billions of rows with minimal aggregation on compute-optimized may complete faster and cheaper than the same query thrashing memory on an undersized memory-optimized instance.

What breaks: memory-optimized instances become wasteful when queries are I/O-bound (waiting on disk reads) or when you're processing streaming data that doesn't benefit from caching. Compute-optimized instances fail when your working set exceeds available RAM and forces spill-to-disk operations, causing severe slowdown. The confusion usually stems from assuming "more memory = faster"—but if your query doesn't actually need to hold data in memory (e.g., sequential table scans with simple filters), you're paying for unused capacity.

## Practice

**Problem:** A daily job computes salary statistics by job title across 500M rows. It groups by `job_title_short`, calculates percentiles (p50, p95, p99), and filters on `job_posted_date`. The query runs in 45 minutes on a small compute-optimized instance, but you're considering upgrading.

```sql
SELECT 
  job_title_short,
  COUNT(*) as job_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as p50_salary,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY salary_year_avg) as p95_salary,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY salary_year_avg) as p99_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_title_short
ORDER BY job_count DESC;
```

**Solution:** Upgrade to memory-optimized because percentile calculations require holding sorted values in memory for each group. Add a pre-aggregation step if possible: materialize the filtered data first, then compute percentiles. If still slow, check if partition pruning on `job_posted_date` is working—many slow queries are actually I/O-bound, not CPU or memory-bound.

## Notes

- **Common mistake:** Right-sizing by instance size alone without profiling query plans. Always check execution breakdown—if 90% of time is I/O wait, more memory won't help.
- **Adjacent topic:** Network-optimized instances matter when shuffling large intermediate results across nodes (Spark, distributed joins); this is separate from the memory vs. compute trade-off.
- **Revisit:** Instance selection is wasted effort without understanding data skew. A few hot partitions (e.g., remote jobs over office jobs) can bottleneck even a well-sized instance.
- **Cost insight:** Memory-optimized instances often cost 2–3× more per unit than compute-optimized. Measure the actual time savings; a 20% speedup on a 2-hour query may not justify the cost.
- **Worth knowing:** Some platforms (Redshift, BigQuery) abstract instance selection; instead, you tune via concurrency slots, resource classes, or reserved capacity—same principle, different levers.
