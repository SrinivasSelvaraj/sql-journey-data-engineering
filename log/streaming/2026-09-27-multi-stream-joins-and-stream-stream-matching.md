---
date: 2026-09-27
phase: streaming
topic: Multi-stream joins and stream-stream matching
---

# Multi-stream joins and stream-stream matching

*Streaming and distributed processing*

## Concept

Multi-stream joins match events from two or more independent, unbounded streams based on keys and time windows. Unlike batch joins where both tables are complete, stream-stream joins must decide *when* to correlate records—typically using a time window (tumbling, sliding, or session) to bound the wait for a matching event from the other stream. Without this temporal boundary, the system would hold state indefinitely, consuming unbounded memory.

Stream-stream joins are critical when you need to correlate causally related events that arrive out of order or at different rates. Examples include matching job applications to job postings, linking user clicks to impressions, or pairing request events with response events. The challenge is that both streams are infinite and may have skew: one stream's events might arrive much later than the other's, requiring you to choose a join window large enough to catch real matches but small enough to keep state manageable.

Without careful windowing, stream-stream joins either lose valid matches (window too small), accumulate unbounded state (window too large), or emit incorrect late-arriving results (no watermark strategy). Watermarks—markers that signal "no events with timestamp *t* or earlier will arrive"—are essential to close windows and emit final results.

## Practice

**Problem:** You have two streams: job postings (arriving as they're published) and application submissions (arriving as candidates apply). You want to match each application to its job posting in real-time and flag applications that arrive more than 90 days after the posting was published.

```sql
WITH postings_windowed AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,
    TUMBLE_START(job_posted_date, INTERVAL '1' DAY) AS window_start,
    TUMBLE_END(job_posted_date, INTERVAL '1' DAY) AS window_end
  FROM job_postings_stream
),
applications_windowed AS (
  SELECT 
    application_id,
    job_id,
    applicant_id,
    application_date,
    TUMBLE_START(application_date, INTERVAL '1' DAY) AS window_start,
    TUMBLE_END(application_date, INTERVAL '1' DAY) AS window_end
  FROM applications_stream
)
SELECT 
  a.application_id,
  a.applicant_id,
  p.job_id,
  p.job_title_short,
  p.salary_year_avg,
  DATE_DIFF(DAY, p.job_posted_date, a.application_date) AS days_after_posting,
  CASE 
    WHEN DATE_DIFF(DAY, p.job_posted_date, a.application_date) > 90 
    THEN 'Late application' 
    ELSE 'On-time' 
  END AS status
FROM applications_windowed a
INNER JOIN postings_windowed p
  ON a.job_id = p.job_id
  AND a.application_date BETWEEN p.job_posted_date AND DATE_ADD(p.job_posted_date, INTERVAL 365 DAY)
WHERE p.job_work_from_home = TRUE
```

## Notes

- **State explosion trap:** Avoid unbounded join windows or missing watermarks—they cause memory leaks. Always set explicit time bounds (e.g., "match within 90 days") and enforce watermark strategy to close windows.

- **Out-of-order handling:** Stream events rarely arrive in timestamp order. Use allowed lateness (grace period) to emit early results, then emit updates for late-arriving data, but finalize the window only after the watermark passes.

- **Key cardinality matters:** If your join key is very high-cardinality (millions of unique values), state grows per-key per-window. Pre-filter or aggregate upstream to reduce key space.

- **Connect to:** Windowing strategies (tumbling, sliding, session), watermarks and event-time semantics, stateful operators, and exactly-once semantics in distributed systems.

- **Revisit:** Practice distinguishing processing-time joins (simpler, less accurate) from event-time joins (correct but require watermarks); test your window sizes with realistic data skew.
