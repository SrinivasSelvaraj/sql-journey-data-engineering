---
date: 2026-11-03
phase: reliability
topic: Volume monitoring: record counts and growth trends
---

# Volume monitoring: record counts and growth trends

*Quality, reliability and the professional layer*

## Concept

Volume monitoring tracks record counts and growth trends across tables to detect data quality issues before they propagate downstream. It answers critical questions: Did yesterday's load complete? Is the growth rate within expected bounds? Did a source system stop sending data? Without it, you discover problems through user complaints or silent data rot in dashboards—both career-limiting outcomes.

The professional layer distinguishes between "the pipeline ran" and "the pipeline ran *correctly*". A failed load might complete 99% of records before erroring; a schema change might cause silent nulls; a source dependency might quietly stop sending data. Volume thresholds and growth trends catch these early, turning reactive firefighting into proactive monitoring.

Effective volume monitoring requires baselines: understanding what "normal" looks like for each table. A 50% drop in daily job postings might indicate missing data or a genuine market shift—the monitor flags it, you investigate. Without baselines, you have alerts without context; with them, you own the data.

## Practice

**Problem**: The `job_postings_fact` table loads daily. You need to detect when daily record counts drop below 80% of the 30-day rolling average (suggesting incomplete data) or when they spike 50% above that average (suggesting duplication or reprocessing).

```sql
WITH daily_counts AS (
  SELECT 
    job_posted_date,
    COUNT(*) as record_count
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '31 days'
  GROUP BY job_posted_date
),
rolling_stats AS (
  SELECT 
    job_posted_date,
    record_count,
    AVG(record_count) OVER (
      ORDER BY job_posted_date 
      ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) as rolling_avg_30d,
    STDDEV(record_count) OVER (
      ORDER BY job_posted_date 
      ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) as rolling_stddev_30d
  FROM daily_counts
)
SELECT 
  job_posted_date,
  record_count,
  rolling_avg_30d,
  ROUND(record_count / rolling_avg_30d, 3) as pct_of_avg,
  CASE 
    WHEN record_count < rolling_avg_30d * 0.8 THEN 'ALERT_LOW'
    WHEN record_count > rolling_avg_30d * 1.5 THEN 'ALERT_HIGH'
    ELSE 'NORMAL'
  END as status
FROM rolling_stats
WHERE job_posted_date = CURRENT_DATE - INTERVAL '1 day'
ORDER BY job_posted_date DESC;
```

## Notes

- **Baseline matters more than thresholds**: A hand-tuned 80% threshold is useless if your baseline includes seasonal spikes. Spend time understanding your data's natural rhythm before alerting on deviations.
- **Growth trends ≠ anomaly detection**: Volume monitoring is deterministic and bounded; it's not machine learning. You're checking "is today within [floor, ceiling]?" not "is today weird?" Keep it simple and explainable.
- **Connects to**: data freshness monitoring (when did the last record arrive?), schema validation (did columns get added/dropped?), and lineage tracking (which upstream dependency broke?). These are the triad of reliability.
- **Common mistake**: Alerting on absolute counts instead of ratios. A 1,000-record drop from 100,000 is noise; the same drop from 2,000 is catastrophic. Always normalize.
- **Revisit quarterly**: Seasonality, source system changes, and business growth shift baselines. A 30-day rolling average protects against transient noise but masks long-term drift—periodically recalibrate thresholds against reality.
