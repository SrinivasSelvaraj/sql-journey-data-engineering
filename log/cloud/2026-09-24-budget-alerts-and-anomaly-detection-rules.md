---
date: 2026-09-24
phase: cloud
topic: Budget alerts and anomaly detection rules
---

# Budget alerts and anomaly detection rules

*Cloud platforms and storage*

## Concept

Budget alerts and anomaly detection rules are automated monitoring systems that flag unexpected cost spikes or query performance degradation in cloud data platforms. They work by establishing baseline thresholds (e.g., "queries should cost <$5" or "daily spend should not exceed $500") and triggering notifications when actual values deviate significantly. Without them, you might discover a runaway query or misconfigured job has cost thousands only after the damage is done—especially dangerous in platforms like BigQuery or Redshift where per-query costs are immediate and cumulative.

The key distinction is between *budget alerts* (spend-based rules) and *anomaly detection rules* (pattern-based deviation). A budget alert catches absolute overspend; an anomaly detection rule catches the *unusual* behavior that often precedes it—like a job that normally scans 100 GB suddenly scanning 10 TB. Together, they form your safety net against both sudden disasters (a forgotten `LIMIT` clause) and slow-burn waste (gradually worsening query efficiency).

## Practice

**Problem:** You are building a reporting pipeline that aggregates job posting salaries by location daily. The query is straightforward but you want to prevent runaway scans if someone accidentally adds an unclustered filter, and you want to alert if daily costs exceed $50.

```sql
-- Create a cost tracking table
CREATE TABLE salary_report_costs (
  run_date DATE,
  bytes_scanned BIGINT,
  query_cost DECIMAL(10,2),
  row_count INT,
  expected_bytes BIGINT
);

-- Daily aggregation query with monitoring columns
INSERT INTO salary_report_costs
SELECT
  CURRENT_DATE() as run_date,
  SUM(OCTET_LENGTH(job_location)) + SUM(OCTET_LENGTH(job_title_short)) + SUM(OCTET_LENGTH(salary_year_avg::text)) as bytes_scanned,
  (SUM(OCTET_LENGTH(job_location)) + SUM(OCTET_LENGTH(job_title_short)) + SUM(OCTET_LENGTH(salary_year_avg::text))) / 1000000000.0 * 6.25 as query_cost,
  COUNT(*) as row_count,
  500000000 as expected_bytes
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE()
  AND salary_year_avg IS NOT NULL;

-- Alert rule: trigger if cost exceeds $50
SELECT 'BUDGET_ALERT' as alert_type, query_cost, run_date
FROM salary_report_costs
WHERE query_cost > 50.00;

-- Anomaly rule: trigger if bytes scanned deviate >200% from baseline
SELECT 'ANOMALY_ALERT' as alert_type, bytes_scanned, expected_bytes, run_date
FROM salary_report_costs
WHERE bytes_scanned > expected_bytes * 3
   OR bytes_scanned < expected_bytes * 0.2;
```

## Notes

- **Baseline calibration is critical:** Set thresholds after observing 2–4 weeks of normal operation, not on day one. A threshold too tight creates alert fatigue; too loose misses real problems.
- **Couple alerts with logs:** An alert without query logs (execution plan, table scans, join order) is just noise. Always store `EXPLAIN` output or query metadata alongside cost tracking.
- **Anomaly detection beats static budgets:** A $50 threshold is fragile if reporting scope grows; a rule like "alert if cost > 2× 7-day rolling average" adapts automatically.
- **Connect to your observability stack:** Integrate alerts into Slack, PagerDuty, or your incident system so they drive action, not just emails that get ignored.
- **Revisit: query optimization basics** (indexing, partitioning, clustering) and **data lineage tracking** to understand which upstream changes caused cost spikes.
