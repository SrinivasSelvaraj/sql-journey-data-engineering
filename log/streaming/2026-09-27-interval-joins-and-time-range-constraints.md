---
date: 2026-09-27
phase: streaming
topic: Interval joins and time range constraints
---

# Interval joins and time range constraints

*Streaming and distributed processing*

## Concept

Interval joins match events from two streams based on time windows rather than exact timestamps. In streaming systems, data arrives out of order and continuously, making traditional joins impossible without defining temporal bounds. An interval join specifies that a record from stream A should only match records from stream B within a specific time window (e.g., "join if event B occurs within 5 minutes before or after event A").

Without interval constraints, you face exploding state: every record from stream A could theoretically match every record from stream B, consuming unbounded memory. You also lose semantic correctness—matching a job application from 2024 with a job posting from 2020 may be technically possible but meaningless. Time range constraints act as a safety valve, discarding old state and ensuring only causally or logically related events combine.

The challenge is tuning the window size correctly. Too narrow and you miss legitimate matches; too wide and state grows and latency increases. This requires domain knowledge: for clickstream data, a 1-second window might suffice, but for supply chain events, hours or days may be necessary.

## Practice

**Problem:** Given `job_postings_fact`, match job postings with applications (from an `applications` stream) that arrive within 30 days of the posting date. Count how many applications each job received in that window.

```sql
SELECT 
    j.job_id,
    j.job_title_short,
    j.job_posted_date,
    COUNT(a.application_id) AS application_count_30d
FROM job_postings_fact j
LEFT JOIN applications a
    ON j.job_id = a.job_id
    AND a.application_date >= j.job_posted_date
    AND a.application_date <= DATE_ADD(j.job_posted_date, INTERVAL 30 DAY)
GROUP BY j.job_id, j.job_title_short, j.job_posted_date;
```

## Notes

- **State management**: Streaming engines (Flink, Spark Streaming) must buffer unmatched records from both streams. Set watermark policies to expire old state; otherwise memory grows indefinitely.
- **Late arrivals**: Define how to handle records arriving after the window closes—typically drop them, or use a side output for manual reconciliation.
- **Asymmetric windows**: Consider whether you want symmetric bounds (±N time units) or asymmetric (only look forward/backward). Application data typically arrives *after* a posting, so a one-sided window (0 to +30 days) is more natural.
- **Skew and ordering**: Even within a window, records may arrive out of order. Use event time (not processing time) and ensure your source provides or you can reconstruct reliable timestamps.
- **Adjacent topics**: Understand watermarks, allowed lateness, and session windows; revisit how your streaming framework's time semantics differ (Kafka timestamps vs. custom event-time fields).
