---
date: 2026-10-22
phase: reliability
topic: Monitoring alert fatigue: threshold tuning and baselines
---

# Monitoring alert fatigue: threshold tuning and baselines

*Quality, reliability and the professional layer*

## Concept

Alert fatigue occurs when monitoring thresholds are set too sensitively, generating noise that desensitizes teams and obscures genuine failures. A pipeline owner must distinguish between legitimate anomalies (data quality issues, upstream delays, schema changes) and normal operational variance. This requires establishing statistical baselines—typical ranges for latency, row counts, null rates, and freshness—then setting thresholds meaningfully above expected fluctuation.

Without threshold tuning, on-call engineers ignore alerts, miss real incidents, and lose trust in the monitoring system. A threshold set at exactly yesterday's value will fire constantly; one set too loose will miss a silent failure. The professional distinction is knowing *why* a threshold exists and *when* to adjust it, not just reacting to alert noise by raising limits until silence returns.

## Practice

**Problem:** Your `job_postings_fact` table is loaded daily. You're alerting on row count changes, but you notice alerts fire 3–4 times per week even though the pipeline succeeds. You need to set a threshold that catches real drops (like a source API outage) but ignores normal variance from job posting seasonality.

```sql
-- Establish baseline: 30-day rolling percentiles
WITH recent_loads AS (
  SELECT
    job_posted_date,
    COUNT(*) as daily_rows
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY job_posted_date
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY daily_rows) as p25,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY daily_rows) as p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY daily_rows) as p75,
  PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY daily_rows) as p5_floor
FROM recent_loads;

-- Set alert threshold at p5 (alerts only on bottom 5% of historical data)
-- Example: if p5 = 8,200 rows, alert when daily load < 8,000 rows
-- This catches genuine failures while allowing normal 10–20% variance
```

## Notes

- **Threshold creep:** Raising limits to silence alerts is backwards; recalibrate baselines instead. If today's threshold no longer fits the data, recalculate percentiles.
- **Seasonality matters:** Job postings spike before holidays or at month-end. Use rolling 90-day windows, not static thresholds, or segment by expected business cycles.
- **Adjacent: SLO definition.** Alerts should tie to service-level objectives, not arbitrary numbers. "99% of daily loads complete before 8am with ≥8k rows" is more defensible than "alert if count drops 15%."
- **Distinguish signal from noise:** Track alert resolution outcomes. If >70% of alerts are non-issues, thresholds are too tight. If you're missing failures, they're too loose.
- **Revisit quarterly:** Data volume, schemas, and upstream behavior drift. Recalculate baselines at least each quarter to keep thresholds anchored to reality.
