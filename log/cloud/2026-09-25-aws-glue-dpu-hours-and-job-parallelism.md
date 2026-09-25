---
date: 2026-09-25
phase: cloud
topic: AWS Glue DPU hours and job parallelism
---

# AWS Glue DPU hours and job parallelism

*Cloud platforms and storage*

## Concept

AWS Glue jobs consume DPU (Data Processing Unit) hours based on the number of worker DPUs allocated and the job duration. A single DPU represents one executor with 4 vCPU and 16 GB memory; jobs are billed per DPU-hour regardless of actual utilization. Parallelism—the number of tasks running concurrently—is determined by available worker count and partition structure. Without understanding this relationship, you either over-provision and waste money or under-provision and wonder why a 10 GB dataset takes 30 minutes.

The critical insight: more DPUs don't always mean faster execution. If your input data has only 4 partitions but you allocate 100 DPUs, 96 sit idle. Conversely, if you have 1000 partitions and only 5 DPUs, you're serializing work. Cost and speed align only when partitions match or slightly exceed DPU worker count. Glue jobs also incur per-DPU initialization overhead (~90 seconds), so micro-jobs on large clusters burn money before the actual work begins.

## Practice

**Problem:** A Glue job that reads `job_postings_fact` (stored as Parquet with 8 partitions by `job_posted_date` month) and filters for remote positions takes 8 minutes end-to-end. The job runs on 10 DPUs and costs $0.44 per run. The team wants to halve execution time and cost.

**Solution:** Reduce worker DPUs to match partition count, since this workload is I/O-bound and embarrassingly parallel:

```sql
-- Glue Job Configuration (Python/PySpark pseudocode)
glueContext.create_dynamic_frame.from_catalog(
    database="data_warehouse",
    table_name="job_postings_fact"
)
# Allocate 8 DPUs (matches 8 partitions) instead of 10
# Each partition processes on one worker; no idle capacity

filtered = dyf.filter(
    lambda x: x["job_work_from_home"] == True
).toDF()

filtered.write.mode("overwrite").parquet(
    "s3://bucket/remote_jobs/"
)
```

Expected outcome: ~4 minutes (linear speedup from reduced startup time; no parallelism gain because already saturated), ~$0.22 cost (2 fewer idle DPUs × 8 minutes).

## Notes

- **Common mistake:** Confusing task parallelism with DPU allocation. Adding DPUs helps only if you have partitions or shuffle stages to distribute; for single-partition reads, one large DPU is more efficient than many small ones.
- **Repartitioning trade-off:** Creating more partitions (via `repartition()` or `coalesce()`) increases scheduling overhead; only worthwhile if DPU count justifies it.
- **Adjacent topics:** Glue bookmarks and job state (avoid re-processing), S3 partitioning schemes (Hive-style vs. custom), and shuffle shuffle vs. map-only jobs (shuffles require all-to-all communication, multiplying cost).
- **Watch for:** Glue Streaming jobs bill differently (per DPU-hour running time, not task time); Spark's lazy evaluation means cost appears at `.write()` or `.collect()`, not at `.filter()`.
- **Revisit when:** Migrating to Glue 4.0+ (Python 3.11, Spark 3.5) or switching to Glue for Ray (serverless, different pricing model entirely).
