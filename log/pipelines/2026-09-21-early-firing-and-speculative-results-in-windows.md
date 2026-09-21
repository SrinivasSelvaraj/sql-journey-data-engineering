---
date: 2026-09-21
phase: pipelines
topic: Early firing and speculative results in windows
---

# Early firing and speculative results in windows

*Pipelines and orchestration*

## Concept

Early firing and speculative results allow windows to emit partial results before all data has arrived, rather than waiting for a complete window to close. Early firing fires when a trigger condition is met inside the open window; speculative results estimate what the final answer *might* be. Without these, you either wait indefinitely for late data (blocking pipelines) or discard it entirely (losing accuracy).

This matters most in streaming pipelines where you can't afford to hold state forever—for example, real-time job market dashboards that report average salaries by location every hour, but postings arrive with variable latency. Early firing lets you publish results at fixed intervals; speculative results let consumers see "this is our best guess right now, but expect refinement." Without them, you choose between stale data (hold until watermark) or incomplete data (drop everything after window close).

Breaking it concretely: if you aggregate job postings per location in 1-hour windows and only emit on window close, dashboards either lag by an hour or miss late-arriving postings. If you emit speculatively every 5 minutes, users see moving averages that converge as data arrives—and can decide whether to trust a "preliminary" result or wait.

## Practice

**Problem:** You need to report average salary by job location in hourly windows, but postings arrive up to 2 hours late. You want dashboards to show preliminary averages every 10 minutes, then refine as data arrives.

```sql
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS window_start,
  job_location,
  COUNT(*) AS posting_count,
  AVG(salary_year_avg) AS avg_salary,
  CURRENT_TIMESTAMP AS result_timestamp,
  CASE 
    WHEN CURRENT_TIMESTAMP < TUMBLE_END(job_posted_date, INTERVAL '1' HOUR) 
    THEN 'speculative'
    WHEN CURRENT_TIMESTAMP < TUMBLE_END(job_posted_date, INTERVAL '1' HOUR) + INTERVAL '2' HOURS
    THEN 'refinement'
    ELSE 'final'
  END AS result_type
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY 
  TUMBLE(job_posted_date, INTERVAL '1' HOUR),
  job_location
EMIT RESULTS EVERY 10 MINUTES
WITH ALLOWED LATENESS INTERVAL '2' HOURS;
```

The `EMIT RESULTS EVERY 10 MINUTES` fires speculatively; `result_type` labels each emission so consumers know confidence level. Allowed lateness keeps the window open to catch late arrivals.

## Notes

- **Session vs. tumbling windows**: speculative results matter more for tumbling (fixed) windows; session windows (data-driven) may not need early emission since they close when gaps appear naturally.
- **Idempotency trap**: every early firing produces a new row. Your sink must handle duplicate keys—upsert to a results table, not append to a log, or downstream gets confused by "refined" vs. "original" numbers.
- **Watermarks and lateness**: early firing ≠ ignoring watermarks. Watermarks still signal "no more data before X time"; allowed lateness extends the grace period. Confusing these causes either zombie windows or unexpected lateness.
- **Consumer contract**: speculative results only help if downstream knows they're provisional. Tag results with version, emission time, or confidence score; otherwise dashboards look broken when numbers shift.
- **Adjacent: sidecar outputs**: when you want speculative *and* final results, write speculative to a temp table and final to the main table. This keeps fast dashboards separate from authoritative reporting.
