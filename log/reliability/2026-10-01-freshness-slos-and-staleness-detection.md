---
date: 2026-10-01
phase: reliability
topic: Freshness SLOs and staleness detection
---

# Freshness SLOs and staleness detection

*Quality, reliability and the professional layer*

## Concept

A Freshness SLO (Service Level Objective) is a commitment that data will not be older than a specified threshold—typically measured from when it was last successfully updated to the current query time. Unlike accuracy or completeness metrics, freshness is about *timeliness*: a dataset can be perfectly correct but useless if it arrives six hours late in a real-time trading system or a recruitment platform.

Staleness detection is the operational practice of monitoring whether your pipelines are meeting those freshness promises. Without it, you discover data is stale only when a business user or dashboard consumer hits a problem—a failure mode that erodes trust and can corrupt downstream decisions. The difference between someone who builds pipelines and someone trusted to own them is often the presence of automated freshness checks that alert *before* stakeholders notice.

Freshness SLOs matter most in systems where recency drives value: hiring platforms where job postings expire, financial systems where market data must be current, or personalization engines where user behavior reflects recent intent. They also matter in batch-heavy architectures where you can't guarantee sub-minute latency but *can* guarantee that your overnight ETL completes before the morning business day begins.

## Practice

**Problem:** Your job_postings_fact table is loaded nightly at 02:00 UTC. Your stakeholders (recruiters and data analysts) need to know that fresh data is available by 06:00 UTC every day. You want to alert if the latest job_posted_date in the table is older than 24 hours *or* if the pipeline itself hasn't completed on time.

```sql
-- Freshness SLO monitoring query
SELECT
  CURRENT_TIMESTAMP AS check_time,
  MAX(job_posted_date) AS latest_job_posted_date,
  CURRENT_TIMESTAMP - MAX(job_posted_date) AS age_since_latest_post,
  EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(job_posted_date))) / 3600 AS age_hours,
  CASE 
    WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(job_posted_date))) / 3600 > 24 
    THEN 'STALE'
    ELSE 'FRESH'
  END AS freshness_status,
  COUNT(*) AS total_job_postings,
  COUNT(*) FILTER (WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days') AS postings_last_7d
FROM job_postings_fact
GROUP BY 1
HAVING EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(job_posted_date))) / 3600 > 24
;

-- Alert trigger: run this after pipeline completion; alert if result set is non-empty
-- Log this to your monitoring system (Datadog, New Relic, CloudWatch, etc.)
```

## Notes

- **Confuse freshness with latency:** Freshness is about data age relative to *now*; latency is about how long the pipeline takes. A batch job can have high latency (runs for 8 hours) but good freshness (completes before the SLO window). Measure both separately.
- **Set SLOs without stakeholder input:** Freshness SLOs are business commitments, not engineering ideals. A 6-hour SLO for a system that can technically deliver 1-hour data is wasteful; a 1-hour SLO for a system built for 6-hour batches will alert constantly and become noise.
- **Monitor only data time, not pipeline time:** Include both the data's observation time (`job_posted_date`) and the pipeline's execution time (when the table was last updated). The former tells you if the *source* is stale; the latter tells you if *your system* is broken.
- **Connects to:** data quality frameworks (freshness is one pillar), SLA/SLO design patterns, observability architecture, and incident response workflows. A stale-data alert is only valuable if it triggers a runbook.
- **Revisit:** how SLOs scale with multiple dependent tables, how to set different SLOs for different user segments (real-time dashboards vs. nightly reports), and how to handle upstream data delays gracefully without falsely alerting your on-call engineer.
