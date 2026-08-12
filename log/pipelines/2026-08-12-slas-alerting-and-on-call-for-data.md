---
date: 2026-08-12
phase: pipelines
topic: SLAs, alerting and on-call for data
---

# SLAs, alerting and on-call for data

*Pipelines and orchestration*

## Concept

Service Level Agreements (SLAs) for data pipelines define acceptable performance and availability thresholds—latency, freshness, accuracy, and uptime. Without them, stakeholders don't know when a pipeline failure is merely inconvenient versus genuinely breaking business operations. Data SLAs differ from API SLAs because data failures often go unnoticed for hours; a report pulls stale numbers silently while users make decisions on bad information.

Alerting and on-call systems transform SLAs from aspirations into enforced commitments. You need multi-layered alerts: upstream task failures (fail loud), data quality violations (freshness, row counts, schema changes), and downstream impact detection (did the dashboard update?). Without alerting tied directly to SLAs, you discover problems reactively—usually when someone asks why the monthly report is wrong.

On-call means owning the alert response. This forces pipeline builders to make systems that can be debugged and fixed under pressure. It's the feedback loop that makes you care about retry logic, idempotency, and clear error messages. Pipelines without on-call responsibility tend to accumulate hidden technical debt until they fail catastrophically.

## Practice

**Problem:** Your `job_postings_fact` table is a core source for salary analysis dashboards updated daily at 06:00 UTC. Yesterday's load failed silently; analysts used day-before data. Today you need to define SLAs and catch this automatically next time.

**Solution:** Create a monitoring query that runs immediately after load completion, then alert if SLA is breached.

```sql
-- Run this as a post-load validation step in orchestration
WITH freshness_check AS (
  SELECT
    MAX(job_posted_date) AS latest_date,
    CURRENT_DATE AS check_date,
    COUNT(*) AS row_count,
    COUNT(DISTINCT job_id) AS unique_jobs
  FROM job_postings_fact
),
sla_status AS (
  SELECT
    CASE 
      WHEN row_count = 0 THEN 'CRITICAL: No data loaded'
      WHEN latest_date < CURRENT_DATE - 1 THEN 'CRITICAL: Data >24h stale'
      WHEN latest_date = CURRENT_DATE - 1 AND unique_jobs < 100 THEN 'WARNING: Low volume load'
      ELSE 'OK'
    END AS status,
    latest_date,
    row_count,
    unique_jobs
  FROM freshness_check
)
SELECT * FROM sla_status
-- Trigger alert if status != 'OK', notify on-call engineer via PagerDuty/Slack
-- Log result to monitoring table for dashboard visibility
```

## Notes

- **SLA creep:** Don't promise 99.9% availability unless you actually own the infrastructure to deliver it. Start conservative (95%, 4-hour latency) and tighten only when proven.
- **Alert fatigue:** Too many low-severity alerts train people to ignore all alerts. Reserve alerts for SLA breaches and critical anomalies; use dashboards for "nice to know" metrics.
- **Idempotency is on-call insurance:** If a pipeline task can safely run twice without duplicating data, your on-call engineer can retry at 3 AM without waking the architect. Build for this from the start.
- **Test your alerts:** Simulate failures in staging and verify the alert fires, routes correctly, and includes enough context (which table, which date, what threshold was breached) to start debugging immediately.
- **Adjacent: data contracts and observability:** SLAs define *what* matters; data contracts codify *how* producers and consumers agree on schema/freshness; observability tools (logs, metrics, traces) provide the *visibility* to prove you're meeting SLAs.
