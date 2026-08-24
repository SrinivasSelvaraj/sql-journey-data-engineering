---
date: 2026-08-24
phase: cloud
topic: Serverless pipelines: Lambda, Cloud Functions, Cloud Run
---

# Serverless pipelines: Lambda, Cloud Functions, Cloud Run

*Cloud platforms and storage*

## Concept

Serverless compute platforms (AWS Lambda, Google Cloud Functions, Cloud Run) execute code without managing infrastructure, charging only for execution time and resources consumed. They're ideal for event-driven workloads—triggered by file uploads, API calls, or scheduled intervals—where you process data in small batches rather than maintaining always-on servers. In data pipelines, they excel at lightweight transformations, API integrations, and triggering downstream jobs, but become expensive and inefficient for long-running, compute-heavy operations.

The critical gotcha is *billing opacity*: you pay per invocation plus per GB-second of memory, so a pipeline that makes 10,000 function calls at 128 MB each costs far more than a single batch job on a VM, even if total CPU time is identical. Without understanding your function's memory footprint, execution duration, and invocation frequency, costs spiral. Additionally, cold starts (container initialization delay) and timeout limits (typically 15 minutes for Lambda, longer for Cloud Run) mean some workloads simply won't fit the model—a 2-hour ETL job isn't serverless-friendly.

## Practice

**Problem:** You need to enrich job posting records by calling an external salary API for each job, then load clean results into a data warehouse. A naive serverless approach invokes a Lambda function once per job posting, but you have 500K postings and discover the monthly bill is $8K despite minimal compute time.

**Solution:** Batch the API calls in larger chunks, process locally where possible, and use asynchronous patterns to reduce invocation count:

```sql
-- Pre-filter and batch in SQL to reduce downstream Lambda calls
WITH jobs_needing_enrichment AS (
  SELECT job_id, job_title_short, job_location
  FROM job_postings_fact
  WHERE salary_year_avg IS NULL
    AND job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
),
batched_jobs AS (
  SELECT 
    ROW_NUMBER() OVER (ORDER BY job_id) / 100 AS batch_id,
    job_id,
    job_title_short,
    job_location
  FROM jobs_needing_enrichment
)
SELECT batch_id, ARRAY_AGG(STRUCT(job_id, job_title_short, job_location)) AS jobs_batch
FROM batched_jobs
GROUP BY batch_id;
```

Invoke Lambda once per batch (5K calls instead of 500K), pass the struct array as a single payload, and have the function enrich all 100 jobs in one API session. This reduces invocations by 98% and cuts costs proportionally.

## Notes

- **Memory = speed and cost:** Allocate more memory to reduce execution time; the CPU scales with memory tier, so 1GB Lambda runs 10× faster than 128 MB but costs only ~2× more—often worth it for I/O-bound tasks.
- **Cold start penalties:** Reuse connections (HTTP keep-alive, database pooling), use provisioned concurrency sparingly, and prefer Cloud Run for latency-sensitive workloads since it auto-scales faster.
- **Batch vs. stream trade-off:** Serverless excels at event-driven triggers, but batching at the source (SQL window functions, stream aggregations) before invoking functions dramatically reduces cost and complexity.
- **Adjacent topics:** Connect to managed data pipelines (Cloud Composer, Dataflow), orchestration patterns (step functions, Pub/Sub), and observability (CloudWatch Logs, X-Ray) to debug slow invocations—a slow API call can't be fixed by tweaking Lambda config.
- **Revisit pricing calculators:** AWS Lambda and Google Cloud's cost estimators change regularly; model your actual invocation and memory patterns quarterly to catch cost drift early.
