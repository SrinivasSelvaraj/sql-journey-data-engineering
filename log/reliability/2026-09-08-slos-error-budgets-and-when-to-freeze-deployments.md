---
date: 2026-09-08
phase: reliability
topic: SLOs, error budgets and when to freeze deployments
---

# SLOs, error budgets and when to freeze deployments

*Quality, reliability and the professional layer*

## Concept

An SLO (Service Level Objective) is a measurable commitment: "this pipeline will be 99.5% available" or "freshness lag won't exceed 4 hours." An error budget is what you *spend* when you miss it—if you're 99.5% available, you earn ~22 minutes of downtime per month. Once spent, you freeze deployments and focus on stability, not features. This is the operational discipline that separates ownership from building.

Without SLOs, you have no signal for when things are actually broken versus slightly slow. Without error budgets, you either over-deploy (shipping bugs constantly) or never deploy (missing business value). The freeze mechanic creates accountability: missing SLO isn't a quiet embarrassment; it's a visible gate that blocks new work until you've earned back trust.

SLOs are not theoretical. They're promises to stakeholders—analytics teams depending on data freshness, ML models requiring consistent feature delivery, compliance systems needing audit trails. Break them twice a quarter, and you've lost the organization's confidence to iterate.

## Practice

**Problem:** Your `job_postings_fact` table powers an hourly refresh dashboard for recruiters. You've committed to 99% uptime and 2-hour maximum freshness lag. Last week you deployed a new column calculation that doubled processing time; the 2-hour window is now violated. You're at 80% of your monthly error budget. Should you deploy the new salary deduplication logic your team built?

**Solution:** No. Implement a deployment freeze until freshness recovers. Monitor the current state, then roll back or optimize the existing change.

```sql
-- Monitor your SLO: freshness check
SELECT 
  MAX(job_posted_date) AS latest_data_in_table,
  CURRENT_TIMESTAMP AS check_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP, MAX(job_posted_date), MINUTE) AS lag_minutes,
  CASE 
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP, MAX(job_posted_date), MINUTE) <= 120 THEN 'OK'
    ELSE 'SLO_BREACH' 
  END AS freshness_status
FROM job_postings_fact
GROUP BY 1, 2;

-- Measure uptime: availability check
WITH job_run_log AS (
  SELECT 
    DATE(run_timestamp) AS run_date,
    COUNT(*) AS total_runs,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successful_runs,
    ROUND(100.0 * SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS uptime_pct
  FROM pipeline_execution_log
  WHERE pipeline_name = 'job_postings_fact'
  GROUP BY run_date
)
SELECT 
  run_date,
  uptime_pct,
  CASE WHEN uptime_pct >= 99.0 THEN 'OK' ELSE 'FREEZE_DEPLOYMENTS' END AS deployment_status
FROM job_run_log
WHERE run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY run_date DESC;
```

Once both checks show green for 12 hours, error budget replenishes and deployments can resume.

## Notes

- **Mistake:** Setting SLOs you can't measure or meet. Start conservative (95% availability, 6-hour freshness). Tighten only after you've proven consistent delivery.
- **Mistake:** Treating error budgets as theoretical. If you breach, act immediately—this isn't a soft guideline, it's the guardrail that keeps operations from decaying.
- **Adjacent:** Incident reviews, on-call rotations, and post-mortems all feed back into SLO calibration. A repeated breach signals the target was wrong or the system is under-resourced.
- **Reconnect:** Error budgets are a forcing function for your alerting strategy. If you can't detect a breach in 15 minutes, your SLO is only as good as your luck.
- **Ownership signal:** Teams that own SLOs ship slower but more reliably. It feels restrictive until you realize it's actually freedom—you deploy confidently because you've already accounted for risk.
