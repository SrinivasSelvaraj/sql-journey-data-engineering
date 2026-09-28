---
date: 2026-09-28
phase: streaming
topic: Session windows and gap-based grouping
---

# Session windows and gap-based grouping

*Streaming and distributed processing*

## Concept

Session windows and gap-based grouping partition a stream into logical groups based on temporal inactivity rather than fixed time intervals. When events arrive out of order or with irregular spacing, you cannot simply tumble data into 5-minute buckets—you need to group consecutive events that are close together, and start a new session when a gap exceeds a threshold. This is essential in streaming contexts because raw event streams often have bursty arrival patterns, late-arriving data, and unpredictable ordering.

Without session windows, you lose the ability to answer questions like "How many consecutive job applications did a recruiter process without a break?" or "What was the user's activity session?" Fixed windows either cut sessions arbitrarily or require post-processing to stitch fragments back together. Gap-based grouping is the native abstraction for this: define a gap duration (e.g., 30 minutes of inactivity), and any events farther apart than that duration start a new session.

In distributed and streaming engines (Spark Structured Streaming, Kafka Streams, Flink), session windows handle watermarking, late arrivals, and state management automatically, but you must understand the cost: session state grows with the number of active sessions and cannot be pruned until the inactivity gap has passed and the window is closed.

## Practice

**Problem:** For each job location, find all periods of continuous job posting activity, where a new session begins whenever more than 7 days pass without a posting. Count postings and compute the salary range per session.

```sql
SELECT
  job_location,
  session_id,
  COUNT(*) as posting_count,
  MIN(salary_year_avg) as min_salary,
  MAX(salary_year_avg) as max_salary,
  MIN(job_posted_date) as session_start,
  MAX(job_posted_date) as session_end
FROM (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_location,
    job_posted_date,
    SUM(CASE 
      WHEN job_posted_date - LAG(job_posted_date) OVER (
        PARTITION BY job_location ORDER BY job_posted_date
      ) > 7 THEN 1 ELSE 0 
    END) OVER (
      PARTITION BY job_location ORDER BY job_posted_date
    ) as session_id
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
)
GROUP BY job_location, session_id
ORDER BY job_location, session_start;
```

## Notes

- **Late arrivals break sessions:** If an event arrives after the inactivity gap has closed, most engines will not retroactively merge it into the previous session. Use watermarking grace periods to handle expected lateness.
- **State explosion risk:** Long-running streams with many unique session keys (e.g., millions of users) can cause memory pressure. Monitor active session count and set aggressive idle timeout policies.
- **Connects to watermarking:** Session windows depend on understanding when a stream is "complete enough" to emit results. Too-early emission loses late events; too-late emission increases latency.
- **Adjacent: Sliding windows and tumbling windows** offer different trade-offs. Sessions adapt to data behavior; fixed windows are simpler but don't capture natural activity clusters.
- **Revisit: Stateful stream processing** — session logic requires maintaining intermediate state across multiple events, which ties directly to checkpoint/recovery and exactly-once semantics.
