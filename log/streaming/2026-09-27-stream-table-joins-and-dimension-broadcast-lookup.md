---
date: 2026-09-27
phase: streaming
topic: Stream-table joins and dimension broadcast lookup
---

# Stream-table joins and dimension broadcast lookup

*Streaming and distributed processing*

## Concept

Stream-table joins enrich fast-moving event streams with slowly-changing reference data. In practice, you have a continuous stream of events (e.g., job applications arriving at 1000/sec) that need context from a dimension table (e.g., job metadata). Without this pattern, you must either denormalize all context into the event itself—creating massive payloads and update nightmares—or perform expensive lookups against a remote database for every single event, which crushes latency.

The key insight: broadcast the dimension table (or a relevant subset) to all stream processors so lookups are local and near-instantaneous. The join happens *in-memory* against the broadcasted state, not over the network. This works because dimension tables are typically orders of magnitude smaller than event streams and change infrequently compared to event velocity.

The challenge emerges when dimensions *do* change: you need a strategy to refresh the broadcast state (versioning, versioned keys, or periodic full reloads) and decide whether a late-arriving dimension change retroactively affects already-processed events or only applies going forward. Get this wrong and you either miss updates entirely or corrupt historical enrichment.

## Practice

**Problem:** A stream of `job_applications(application_id, job_id, applicant_id, application_timestamp)` arrives at high volume. You need to enrich each application with the job's `job_title_short` and `salary_year_avg`. The job metadata changes occasionally (salary updates, title corrections), but you cannot afford a synchronous lookup for every application.

```sql
-- In a streaming framework like Flink, Kafka Streams, or Spark Structured Streaming:

-- Step 1: Load dimension as broadcast state (runs once or on refresh schedule)
job_postings_broadcast = broadcast(
  SELECT job_id, job_title_short, salary_year_avg, job_location
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90' DAY
)

-- Step 2: Stream-table join using local lookup
SELECT
  a.application_id,
  a.job_id,
  a.applicant_id,
  j.job_title_short,
  j.salary_year_avg,
  a.application_timestamp
FROM job_applications a
JOIN job_postings_broadcast j
  ON a.job_id = j.job_id
```

In Spark Structured Streaming, this becomes:
```python
job_dim = spark.read.parquet("s3://jobs_dimension/").repartition(1).cache()
job_dim_broadcast = broadcast(job_dim)

enriched = (applications_stream
  .join(job_dim_broadcast, "job_id", "left")
  .select("application_id", "job_id", "job_title_short", "salary_year_avg"))
```

## Notes

- **Broadcast size matters:** If your dimension table exceeds available memory on executors, the broadcast fails silently or spills to disk (defeating the purpose). Profile and filter aggressively.
- **Versioning stale data:** When a job title changes, old applications already processed keep the old title. Decide if this is correct (usually yes—capture what was true at application time) or if you need a *versioned dimension* with effective dates to retroactively join.
- **Broadcast refresh strategy:** Use time-based triggers (reload every 1 hour) or event-based triggers (reload when dimension changelog appears) rather than reloading on every micro-batch.
- **Left vs. inner join risk:** Using `INNER JOIN` drops applications for jobs not in the broadcast set; `LEFT JOIN` preserves them but may have null enrichment. Choose deliberately based on data quality assumptions.
- **Related pattern—slowly changing dimensions (SCD):** Type 2 SCD with effective dates is the enterprise standard for handling dimension history; stream-table joins become more complex when you must join on both key *and* temporal validity.
