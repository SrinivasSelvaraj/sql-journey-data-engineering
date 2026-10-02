---
date: 2026-10-02
phase: reliability
topic: Timeliness SLOs and latency percentiles
---

# Timeliness SLOs and latency percentiles

*Quality, reliability and the professional layer*

## Concept

A timeliness SLO (Service Level Objective) defines when data must be available, not just that it works. It's the contract between your pipeline and its consumers: "Analytics queries on job postings will reflect posted jobs within 4 hours" or "Real-time dashboards show postings within 15 minutes." Without this, you have no way to know if a 2-hour delay is acceptable or a breach—and consumers plan budgets, hiring decisions, and product features around invisible assumptions about freshness.

Latency percentiles matter because averages hide tail behavior. A pipeline that delivers in 5 minutes 99% of the time but occasionally takes 3 hours has failed its users when it matters most (during hiring surges, board meetings, or automated alerting). P95 and P99 latencies tell you what your worst customers actually experience; they're the SLO you should defend, not the mean.

Without timeliness SLOs, pipelines become black boxes. You don't know if slow refresh is a problem or feature. You can't prioritize fixes. You can't explain to the hiring team why their job board is stale. You own it when you can measure it and commit to it.

## Practice

**Problem:** Your `job_postings_fact` table feeds a real-time job board and an internal hiring dashboard. The board needs postings within 15 minutes (P99); the dashboard can tolerate 4 hours (P95). Your current pipeline loads every 30 minutes with no monitoring. How do you instrument it to track and alert on SLO breaches?

```sql
-- Create a monitoring table to track pipeline latency
CREATE TABLE IF NOT EXISTS pipeline_slo_tracking (
  pipeline_run_id STRING,
  pipeline_name STRING,
  job_posted_date DATE,
  data_loaded_at TIMESTAMP,
  latency_minutes INT,
  slo_tier STRING, -- 'realtime_board' or 'analytics_dashboard'
  slo_threshold_minutes INT,
  breached BOOLEAN,
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Track latency after your load job completes
INSERT INTO pipeline_slo_tracking
SELECT
  GENERATE_UUID() as pipeline_run_id,
  'job_postings_fact_load' as pipeline_name,
  MAX(job_posted_date) as latest_job_posted,
  CURRENT_TIMESTAMP() as data_loaded_at,
  CAST((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(job_posted_date))) / 60 AS INT) as latency_minutes,
  CASE 
    WHEN CAST((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(job_posted_date))) / 60 AS INT) <= 15 
      THEN 'realtime_board' 
    WHEN CAST((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(job_posted_date))) / 60 AS INT) <= 240 
      THEN 'analytics_dashboard' 
  END as slo_tier,
  CASE 
    WHEN CAST((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(job_posted_date))) / 60 AS INT) <= 15 THEN 15
    ELSE 240
  END as slo_threshold_minutes,
  CAST((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(job_posted_date))) / 60 AS INT) > 240 as breached
FROM job_postings_fact
GROUP BY 1;

-- Query P95 and P99 latencies to set realistic SLOs
SELECT
  slo_tier,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY latency_minutes) as p50_minutes,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_minutes) as p95_minutes,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_minutes) as p99_minutes,
  SUM(CASE WHEN breached THEN 1 ELSE 0 END) as breach_count,
  COUNT(*) as total_runs,
  ROUND(100.0 * SUM(CASE WHEN breached THEN 1 ELSE 0 END) / COUNT(*), 2) as breach_percent
FROM pipeline_slo_tracking
WHERE loaded_at >= CURRENT_TIMESTAMP - INTERVAL 30 DAY
GROUP BY slo_tier;
```

## Notes

- **Mean latency hides disasters**: A pipeline averaging 10 minutes can miss P99 SLOs if one run takes 2 hours weekly. Always monitor percentiles, not just averages.
- **SLOs must be measurable and owned**: Vague ("fast") isn't an SLO. Concrete targets ("P99 < 15 min") with owners and escalation paths are. Your S
