---
date: 2026-09-08
phase: reliability
topic: Alert fatigue: tuning thresholds and reducing noise
---

# Alert fatigue: tuning thresholds and reducing noise

*Quality, reliability and the professional layer*

## Concept

Alert fatigue occurs when monitoring systems trigger too many alerts—especially false positives or low-severity warnings—causing teams to ignore or dismiss even critical signals. This is the difference between *having* monitoring and *trusting* monitoring. A pipeline that alerts on every minor delay or single-row discrepancy will train people to ignore all alerts; a pipeline that fails silently is worse, but not by much.

The cost is organizational: on-call rotations lose credibility, incidents go unnoticed, and engineers develop alert blindness. This matters most when you move from "my script runs" to "my script runs reliably enough that others depend on it." It's the moment you stop being a builder and start being a steward.

Without tuning thresholds, you either over-alert (noise) or under-alert (silence). The skill is knowing the difference between a signal worth waking someone up for and a normal fluctuation worth logging quietly. That judgment comes from understanding your data's baseline, seasonal patterns, and what actually requires human intervention versus what can auto-heal or be handled in batch reviews.

## Practice

**Problem:** Your `job_postings_fact` table loads daily. You want to alert on data quality issues—but not every small deviation. You're currently alerting when row counts drop by even 1%, which fires almost weekly due to weekend posting patterns. You need thresholds that catch real problems (schema changes, source failures) without noise.

```sql
-- Calculate baseline and variability first
WITH daily_stats AS (
  SELECT
    job_posted_date,
    COUNT(*) as row_count,
    COUNT(DISTINCT job_location) as unique_locations,
    ROUND(AVG(salary_year_avg), 0) as avg_salary
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY job_posted_date
),
baseline AS (
  SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY row_count) as median_rows,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY row_count) as q1_rows,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY row_count) as q3_rows,
    (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY row_count) 
     - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY row_count)) as iqr
  FROM daily_stats
)
SELECT
  ds.job_posted_date,
  ds.row_count,
  CASE
    WHEN ds.row_count < (b.q1_rows - 1.5 * b.iqr)
      THEN 'CRITICAL: row count below lower fence'
    WHEN ds.row_count = 0
      THEN 'CRITICAL: no data loaded'
    WHEN COUNT(DISTINCT ds.job_location) = 0
      THEN 'WARNING: no location data'
    WHEN ds.avg_salary IS NULL
      THEN 'WARNING: salary nulls detected'
    ELSE 'OK'
  END as alert_level
FROM daily_stats ds
CROSS JOIN baseline b
WHERE ds.job_posted_date = CURRENT_DATE - INTERVAL '1 day'
ORDER BY ds.job_posted_date DESC;
```

This approach uses IQR (interquartile range) to define thresholds based on actual variance rather than fixed percentages. Weekend dips won't trigger alerts; a complete source failure will.

## Notes

- **Mistake:** Setting thresholds on gut feeling or a single bad day of data. Always calculate baselines over 60–90 days to account for cyclical patterns (weekdays vs. weekends, seasonal hiring, etc.).
- **Mistake:** Alerting on raw metrics instead of anomalies. A 5% drop in row count means nothing without context; a 5-sigma deviation from your 90-day median means something.
- **Connection:** This feeds into incident response procedures—make sure your alert routing is clear so the right person is on-call, or noise will get worse.
- **Revisit:** As your data grows or business context shifts, re-baseline quarterly. What's normal for Q1 hiring may not be normal for Q4; old thresholds become stale.
- **Adjacent skill:** Learn to distinguish between alerts that need *immediate* action (schema changes, total failures) and those that need *investigation* (gradual drift, one-off anomalies). Route them differently.
