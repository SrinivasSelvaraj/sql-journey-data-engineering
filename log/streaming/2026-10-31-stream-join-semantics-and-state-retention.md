---
date: 2026-10-31
phase: streaming
topic: Stream join semantics and state retention
---

# Stream join semantics and state retention

*Streaming and distributed processing*

## Concept

Stream joins combine data arriving from two or more sources, but unlike batch joins, the streams have no defined endpoints and records arrive out of order. A stream join must maintain *state*—a buffer of unmatched records from one stream—waiting for matching records from the other. Without this state, you lose the ability to correlate events: a user click arrives before the corresponding product view, or a job application arrives before the job posting itself.

State retention policies determine how long to keep buffered records. If you retain too little, legitimate late-arriving matches are missed. If you retain too long, memory grows unbounded. The join semantics—inner, left, right, or outer—affect which unmatched records eventually emit as results and when they're safe to discard. In practice, you must define a maximum staleness window (e.g., "match applications to postings within 30 days") or risk either data loss or resource exhaustion.

This matters most when joining fast-changing reference data (job postings) with event streams (job applications). A new job posting is added to a stream, then days later applications arrive for that job. Without correct state retention and join semantics, you either discard the application or forget the job posting details.

## Practice

**Problem:** You have a stream of `job_postings_fact` arriving in real-time, and a separate stream of `job_applications` (application_id, job_id, applicant_id, application_timestamp). You need to enrich each application with the job posting details. Applications can arrive up to 7 days after the posting. Design a stream join that handles late-arriving applications while bounding memory usage.

```sql
-- Pseudo-code for stream join with state retention (e.g., Kafka Streams / Flink SQL)

CREATE TABLE job_postings_stream (
  job_id STRING,
  job_title_short STRING,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location STRING,
  event_time TIMESTAMP(3),
  WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'postings'
);

CREATE TABLE job_applications_stream (
  application_id STRING,
  job_id STRING,
  applicant_id STRING,
  application_timestamp TIMESTAMP(3),
  WATERMARK FOR application_timestamp AS application_timestamp - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'applications'
);

-- Left outer join: keep postings even if no application arrives within window
SELECT
  a.application_id,
  a.applicant_id,
  p.job_id,
  p.job_title_short,
  p.salary_year_avg,
  p.job_work_from_home,
  a.application_timestamp
FROM job_applications_stream a
LEFT JOIN job_postings_stream FOR SYSTEM_TIME AS OF a.application_timestamp AS p
  ON a.job_id = p.job_id
  AND p.event_time BETWEEN a.application_timestamp - INTERVAL '7' DAY 
                       AND a.application_timestamp;
```

The `WATERMARK` defines the allowed lateness (5 seconds of clock skew). The `FOR SYSTEM_TIME AS OF` clause looks up posting state at the application's arrival time. The `BETWEEN` condition bounds state retention to 7 days before application arrival, preventing unbounded memory growth while allowing late applications.

## Notes

- **State explosion trap:** If you join two infinite streams without a retention window, state grows forever. Always pair joins with a time-bounded predicate or explicit state TTL configuration.
- **Watermark sensitivity:** Watermarks signal "no earlier data will arrive." If your watermark advances too fast, you discard late-arriving matches; too slow, you bloat state. Tune based on observed lateness in your data pipeline.
- **Inner vs. outer semantics:** Inner joins emit only when both sides match *within the window*; outer joins emit partially-matched records when the later stream's watermark passes the retention boundary. Choose based on whether unmatched records are valid outputs.
- **Adjacent topics:** Stream state backends (RocksDB, in-memory), changelog topics for fault tolerance, and the concept of event time vs. processing time all interact with join semantics.
- **Revisit:** Test with out-of-order injection and replay realistic lateness distributions; synthetic tests often miss edge cases in production timing.
