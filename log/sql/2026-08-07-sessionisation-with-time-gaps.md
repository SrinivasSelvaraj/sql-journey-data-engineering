---
date: 2026-08-07
phase: sql
topic: Sessionisation with time gaps
---

# Sessionisation with time gaps

*SQL for analytics and engineering*

## Concept

Sessionisation with time gaps is the process of grouping sequential events into distinct sessions when a time threshold is exceeded. Without it, you treat all user/entity activity as one continuous stream; with it, you recognize that a gap (e.g., 30+ minutes of inactivity) signals a meaningful boundary—a new browsing session, a separate support ticket interaction, or distinct job search intent.

This matters in analytics when you need to measure engagement per session rather than per user, or when you're reconstructing user journeys. Without proper sessionisation, metrics like "average actions per session" become meaningless, and funnel analysis breaks because you can't distinguish one coherent activity sequence from another.

The typical SQL approach uses `LAG()` to detect when the time gap between consecutive events exceeds your threshold, then assigns a session ID using `SUM(gap_flag) OVER (PARTITION BY user_id ORDER BY event_time)`. This works because incrementing a running sum at each new gap creates a unique session identifier.

## Practice

**Problem:** Given `job_postings_fact`, assume a user views multiple job postings over time. Create sessions where each session ends if more than 7 days pass without a new view. For each session, count distinct job titles viewed and calculate the session's date span.

```sql
WITH job_views AS (
  SELECT
    job_location,
    job_title_short,
    job_posted_date,
    LAG(job_posted_date) OVER (PARTITION BY job_location ORDER BY job_posted_date) AS prev_date
  FROM job_postings_fact
),
gaps_flagged AS (
  SELECT
    job_location,
    job_title_short,
    job_posted_date,
    CASE
      WHEN prev_date IS NULL THEN 1
      WHEN job_posted_date - prev_date > 7 THEN 1
      ELSE 0
    END AS gap_flag
  FROM job_views
),
sessions AS (
  SELECT
    job_location,
    job_title_short,
    job_posted_date,
    SUM(gap_flag) OVER (PARTITION BY job_location ORDER BY job_posted_date) AS session_id
  FROM gaps_flagged
)
SELECT
  job_location,
  session_id,
  COUNT(DISTINCT job_title_short) AS distinct_titles,
  MIN(job_posted_date) AS session_start,
  MAX(job_posted_date) AS session_end,
  MAX(job_posted_date) - MIN(job_posted_date) AS session_span_days
FROM sessions
GROUP BY job_location, session_id
ORDER BY job_location, session_start;
```

## Notes

- **Gap detection placement:** The `LAG()` must be ordered by the same timestamp used in the gap calculation; mismatched ordering breaks everything.
- **Session ID uniqueness:** `SUM(gap_flag)` only creates unique IDs *within* a partition (e.g., per user/location); you must include the partition key in the final `GROUP BY`.
- **Off-by-one with NULL:** The first event always has `prev_date = NULL`, so explicitly handle it in the `CASE` statement; forgetting this creates misaligned sessions.
- **Adjacent topics:** This connects to event funnel analysis, customer lifetime value (CLV) cohort windows, and churn detection—all require clean session boundaries.
- **Performance consideration:** On large tables, window functions are efficient, but ensure the partition key is indexed; consider materialized intermediate tables if you're chaining multiple window operations.
