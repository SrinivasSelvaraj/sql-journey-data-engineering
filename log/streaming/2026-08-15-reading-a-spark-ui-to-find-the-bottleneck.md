---
date: 2026-08-15
phase: streaming
topic: Reading a Spark UI to find the bottleneck
---

# Reading a Spark UI to find the bottleneck

*Streaming and distributed processing*

## Concept

The Spark UI displays real-time metrics across jobs, stages, and tasks, enabling you to pinpoint where processing time is actually spent. In streaming workloads, bottlenecks often hide in shuffle operations, skewed partitions, or inefficient joins—problems that don't surface in small test runs but cripple production pipelines handling continuous data. Without reading the UI systematically, you may optimize the wrong component and leave latency or resource waste unaddressed.

Start by examining the Jobs tab to identify which stage consumes the most wall-clock time. Then drill into the Stages tab, sorting by duration and shuffle read/write metrics. For streaming, pay special attention to task skew: if one partition processes 10× more data than others, a few tasks become the bottleneck. The Executors tab reveals whether you have enough resources or whether GC pauses and memory pressure are the real culprit.

## Practice

**Problem:** A streaming pipeline ingests job postings and aggregates salary statistics by location. The query runs but takes 45 seconds per micro-batch when the source delivers data every 10 seconds. You need to find why the pipeline cannot keep up.

```sql
SELECT 
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  MAX(salary_year_avg) as max_salary
FROM job_postings_fact
WHERE job_posted_date >= current_date - INTERVAL 30 DAY
  AND job_work_from_home = FALSE
GROUP BY job_location
```

**Solution:** Run the query as a streaming trigger and open the Spark UI. Check the Stages tab and note that the GroupByKey stage shows 80% of execution time, with task durations ranging from 2s to 28s (severe skew). The shuffle read/write metrics indicate uneven partition distribution across locations. Repartition before the grouping and consider salting high-cardinality locations to spread load evenly:

```sql
SELECT 
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  MAX(salary_year_avg) as max_salary
FROM (
  SELECT 
    job_location,
    salary_year_avg,
    ROW_NUMBER() OVER (PARTITION BY job_location ORDER BY job_id) as rn
  FROM job_postings_fact
  WHERE job_posted_date >= current_date - INTERVAL 30 DAY
    AND job_work_from_home = FALSE
)
GROUP BY job_location
```

Alternatively, increase the number of shuffle partitions in your Spark config and monitor the UI again until task durations converge.

## Notes

- **Task skew is the silent killer:** Even if average task time looks good, one slow task blocks the entire stage. Always check the max duration in the Stages tab, not just the mean.
- **Shuffle metrics matter more in streaming:** Streaming pipelines are latency-sensitive; a large shuffle operation can push you past your micro-batch interval and cause backpressure to build up.
- **GC pauses hide in the executor logs:** If you see many short tasks followed by a long gap, check the Executors tab and logs for "Full GC"; this often means you need more memory or smaller batches.
- **Adjacent topic: Adaptive Query Execution (AQE)** automatically adjusts partition counts and join strategies at runtime; enable it to reduce manual tuning of shuffle partitions.
- **Revisit watermarking and late data:** The UI shows processing time, not event time; combine UI analysis with watermark monitoring to catch delayed arrivals that slow aggregation windows.
