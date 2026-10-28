---
date: 2026-10-28
phase: pipelines
topic: SLA monitoring and alert escalation
---

# SLA monitoring and alert escalation

*Pipelines and orchestration*

## Concept

SLA monitoring and alert escalation ensure data pipelines meet agreed-upon service levels and notify the right people when they don't. An SLA (Service Level Agreement) defines acceptable thresholds: how long a pipeline can take, what freshness is required, acceptable error rates, or data quality gates. Without explicit monitoring, failures hide in logs until downstream stakeholders discover stale or corrupted data, which erodes trust and causes operational chaos.

Alert escalation matters because a 2 AM pipeline failure needs different handling than a 2 PM one. You define severity levels (warning → critical), assign owners, and route alerts through appropriate channels (Slack for info, PagerDuty for pages, dashboards for visibility). The goal is fast detection and fast remediation before SLA breach impacts analytics, reporting, or dependent systems.

Robust escalation prevents alert fatigue while ensuring no breach goes unaddressed. This requires tiered thresholds (e.g., alert at 90% of allowed runtime, page if 100% exceeded), runbook links so responders know what to do, and post-mortems so recurring issues get fixed rather than repeatedly escalated.

## Practice

**Problem:** The `job_postings_fact` table must refresh daily by 6 AM. You need to monitor (1) whether the load completes within 2 hours, (2) whether row counts dropped by >20% (suggesting a data quality issue), and (3) escalate if both conditions fail.

```sql
-- Create SLA monitoring table
CREATE TABLE sla_checks (
  check_id INT PRIMARY KEY AUTO_INCREMENT,
  table_name VARCHAR(100),
  check_type VARCHAR(50),
  threshold_value VARCHAR(100),
  check_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  actual_value VARCHAR(100),
  passed BOOLEAN,
  severity VARCHAR(20)
);

-- Log load duration and row count after job completes
INSERT INTO sla_checks (table_name, check_type, threshold_value, actual_value, passed, severity)
SELECT 
  'job_postings_fact',
  'load_duration_minutes',
  '120',
  TIMESTAMPDIFF(MINUTE, @load_start, NOW()),
  TIMESTAMPDIFF(MINUTE, @load_start, NOW()) <= 120,
  CASE WHEN TIMESTAMPDIFF(MINUTE, @load_start, NOW()) > 120 THEN 'critical' ELSE 'ok' END
WHERE TRUE;

-- Check row count against previous day
INSERT INTO sla_checks (table_name, check_type, threshold_value, actual_value, passed, severity)
SELECT 
  'job_postings_fact',
  'row_count_drop',
  '20%',
  CONCAT(
    ROUND(
      (1 - (SELECT COUNT(*) FROM job_postings_fact) / 
            (SELECT COUNT(*) FROM job_postings_fact_prev_day)) * 100, 
      1
    ), 
    '%'
  ),
  (1 - (SELECT COUNT(*) FROM job_postings_fact) / 
        (SELECT COUNT(*) FROM job_postings_fact_prev_day)) * 100 <= 20,
  CASE WHEN (1 - (SELECT COUNT(*) FROM job_postings_fact) / 
                  (SELECT COUNT(*) FROM job_postings_fact_prev_day)) * 100 > 20 THEN 'critical' ELSE 'ok' END;

-- Escalation logic: alert if any critical check failed
SELECT *
FROM sla_checks
WHERE passed = FALSE AND severity = 'critical' AND check_timestamp > DATE_SUB(NOW(), INTERVAL 1 DAY)
ORDER BY check_timestamp DESC;
```

Trigger a PagerDuty incident or send a Slack message via webhook when the query above returns rows.

## Notes

- **Alert fatigue kills responsiveness.** Tune thresholds so you page on true problems (e.g., 150% of normal runtime) not normal variance; use warnings for yellow zones.
- **SLAs must be negotiated with stakeholders.** A 6 AM deadline is meaningless if the pipeline takes 3 hours—agree on realistic targets upfront or plan to add capacity.
- **Escalation is a process, not just a tool.** Define who owns what (data eng for pipeline failures, analytics eng for data quality, PM for business logic), and link runbooks so responders don't waste time guessing.
- **Connect SLA checks to data quality tests.** Row count drops often signal truncation bugs or upstream failures; automate dbt or Great Expectations tests *before* escalation happens.
- **Revisit after incidents.** If you breach SLA, post-mortem to understand if thresholds were wrong, monitoring was missing, or the pipeline genuinely needs optimization.
