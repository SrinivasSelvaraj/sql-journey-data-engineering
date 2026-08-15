---
date: 2026-08-15
phase: streaming
topic: Spark: caching, persistence and spill
---

# Spark: caching, persistence and spill

*Streaming and distributed processing*

## Concept

In Spark, **caching** (via `.cache()` or `.persist()`) stores a DataFrame or RDD in memory after first evaluation, so subsequent actions reuse that data without recomputing the lineage. **Persistence levels** control where data lives—MEMORY_ONLY, MEMORY_AND_DISK, DISK_ONLY—trading speed for fault tolerance. **Spill** occurs when Spark runs out of memory during shuffle operations and writes intermediate data to disk, dramatically slowing execution.

Caching matters most when a DataFrame is referenced multiple times in the same application: without it, Spark re-executes the entire transformation chain for each action. In streaming contexts, caching becomes critical for windowed aggregations, stateful operations, and joins that must hold micro-batch data across multiple stages. Without strategic caching, you pay redundant CPU and I/O costs; without adequate memory allocation, spill forces the cluster into disk-based shuffle hell, turning millisecond-latency operations into second-scale bottlenecks.

The key tradeoff: caching consumes executor memory (reducing space for active computations), but prevents recomputation. For large streaming pipelines with multiple branches or repeated filters, caching the filtered result upstream saves more CPU than it costs in memory overhead.

## Practice

**Problem:** You run daily batch reporting on job postings. You filter for remote work, high-salary roles (>$120k), and then fork into two reports: (1) count by job_title_short, and (2) average salary by job_location. Without caching, the filter runs twice. With a large dataset and memory constraints, the shuffle for aggregations may spill to disk.

```sql
-- Without caching (inefficient)
SELECT job_title_short, COUNT(*) as count
FROM job_postings_fact
WHERE job_work_from_home = true AND salary_year_avg > 120000
GROUP BY job_title_short;

SELECT job_location, AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_work_from_home = true AND salary_year_avg > 120000
GROUP BY job_location;

-- With caching (Spark/DataFrame API)
filtered_df = spark.read.table("job_postings_fact") \
  .filter((col("job_work_from_home") == True) & (col("salary_year_avg") > 120000)) \
  .persist(StorageLevel.MEMORY_AND_DISK)

report1 = filtered_df.groupBy("job_title_short").count()
report2 = filtered_df.groupBy("job_location").agg(avg("salary_year_avg"))

report1.write.mode("overwrite").saveAsTable("remote_high_pay_by_title")
report2.write.mode("overwrite").saveAsTable("remote_high_pay_by_location")

filtered_df.unpersist()  -- free memory when done
```

## Notes

- **Unpersist or set TTL:** Always call `.unpersist()` after using a cached DataFrame, or set a timeout; otherwise stale data consumes executor memory indefinitely and causes OOM errors.
- **Spill tuning:** Increase `spark.sql.shuffle.partitions` (default 200) to reduce per-partition size; raise executor memory or use MEMORY_AND_DISK persistence to let Spark gracefully spill rather than crash.
- **Streaming state:** In Structured Streaming with `.applyInPandasUDF()` or stateful operations, micro-batch intermediate results are implicitly cached; monitor executor memory and checkpoint state to HDFS/S3 to prevent data loss on failure.
- **Cache invalidation:** After a cache, downstream transformations operate on the cached version—if source data changes, the cache is stale. Use `.unpersist()` between test iterations.
- **Adjacent: Checkpointing** is Spark's fault-tolerance mechanism (separate from caching); it writes RDD lineage to reliable storage. Streaming queries combine both: cache for speed within a micro-batch, checkpoint for recovery across batches.
