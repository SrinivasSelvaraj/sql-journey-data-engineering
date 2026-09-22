---
date: 2026-09-22
phase: pipelines
topic: SLA monitoring and alert routing rules
---

# SLA monitoring and alert routing rules

*Pipelines and orchestration*

## Concept

SLA monitoring and alert routing rules define acceptable performance thresholds for data pipelines and automatically escalate failures to the right teams. An SLA (Service Level Agreement) specifies constraints like "daily ETL must complete by 6 AM" or "data freshness lag must not exceed 2 hours." Without explicit SLAs and routing, failures either go unnoticed (stale data reaches users) or trigger alert fatigue (every minor delay pages oncall).

Effective alert routing means routing depends on failure *type* and *severity*. A 10-minute delay might warrant a Slack message to the data team; a 4-hour delay to production tables should page the engineering oncall. Similarly, a failed external API call (retriable) routes differently than a schema validation error (requires manual investigation). The pipeline itself must emit structured metadata—execution time, row counts, data quality checks—so rules can evaluate conditions at query time.

Without this layer, you lose observability: you don't know your pipeline is degrading until users complain, and when alerts do fire, no one knows who should fix it or how urgent it is. This is especially critical for fact tables like job postings where staleness directly impacts downstream analytics.

## Practice

**Problem:** Your `job_postings_fact` ingestion runs nightly at 11 PM. The SLA requires new postings to be queryable by 6 AM with <1% data loss (compared to raw source count). You need to:
1. Detect if ingestion finishes after 5:30 AM (30-minute buffer before SLA breach)
2. Alert if row count drops >1% between source and fact table
3. Route high-severity alerts (SLA breach) to #data-incidents Slack channel; low-severity (warnings) to #data-team

```sql
-- Create SLA monitoring table
CREATE TABLE pipeline_sla_rules (
  sla_id STRING,
  pipeline_name STRING,
  target_completion_time TIME,
  warning_threshold_minutes INT,
  critical_threshold_minutes INT,
  max_acceptable_data_loss_pct DECIMAL(5,2),
  alert_channel STRING,
  severity_on_breach STRING
);

INSERT INTO pipeline_sla_rules VALUES
  ('job_postings_daily', 'job_postings_ingestion', '06:00:00', 30, 0, 1.0, '#data-incidents', 'CRITICAL');

-- Create pipeline execution log
CREATE TABLE pipeline_execution_log (
  execution_id STRING,
  pipeline_name STRING,
  source_row_count INT,
  fact_row_count INT,
  start_time TIMESTAMP,
  end_time TIMESTAMP,
  status STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Alert routing logic (run post-pipeline)
SELECT
  r.sla_id,
  r.pipeline_name,
  l.execution_id,
  CASE
    WHEN EXTRACT(HOUR FROM l.end_time) > 5 OR 
         (EXTRACT(HOUR FROM l.end_time) = 5 AND EXTRACT(MINUTE FROM l.end_time) > 30)
      THEN 'CRITICAL: SLA breach—completed after 5:30 AM'
    WHEN ((l.source_row_count - l.fact_row_count) * 100.0 / l.source_row_count) > r.max_acceptable_data_loss_pct
      THEN 'CRITICAL: Data loss exceeds ' || r.max_acceptable_data_loss_pct || '%'
    ELSE 'WARNING: Completed within SLA but near threshold'
  END AS alert_message,
  CASE
    WHEN EXTRACT(HOUR FROM l.end_time) > 5 OR 
         (EXTRACT(HOUR FROM l.end_time) = 5 AND EXTRACT(MINUTE FROM l.end_time) > 30) OR
         ((l.source_row_count - l.fact_row_count) * 100.0 / l.source_row_count) > r.max_acceptable_data_loss_pct
      THEN '#data-incidents'
    ELSE '#data-team'
  END AS route_to_channel,
  DATEDIFF(MINUTE, l.start_time, l.end_time) AS duration_minutes,
  ROUND(((l.source_row_count - l.fact_row_count) * 100.0 / l.source_row_count), 2) AS data_loss_pct
FROM pipeline_execution_log l
JOIN pipeline_sla_rules r ON l.pipeline_name = r.pipeline_name
WHERE l.created_at >= CURRENT_DATE - INTERVAL 1 DAY;
```

## Notes

- **Alert fatigue kills observability**: If every pipeline delay triggers a page, oncall stops trusting alerts. Set thresholds realistically based on actual business impact and downstream SLAs.
- **Routing isn't just severity**: Route by owner too—a schema error on the `job_location
