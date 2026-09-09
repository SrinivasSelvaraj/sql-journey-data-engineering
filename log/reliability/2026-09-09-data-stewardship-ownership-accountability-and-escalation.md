---
date: 2026-09-09
phase: reliability
topic: Data stewardship: ownership, accountability and escalation
---

# Data stewardship: ownership, accountability and escalation

*Quality, reliability and the professional layer*

## Concept

Data stewardship transforms a data engineer from a builder into an owner. It means being accountable for data quality not just at pipeline execution, but across its entire lifecycle—understanding who depends on it, why it matters, and what happens when it breaks. Ownership surfaces the gap between "does this run?" and "can I trust this?" A steward documents assumptions, monitors for drift, and knows the business impact of a schema change.

This matters most when data feeds critical decisions: hiring, pricing, compliance, or resource allocation. Without stewardship, you get silent failures—a salary field that stops updating, a location field that gets geocoded incorrectly, a date field that drifts timezone-unaware. The person who built the pipeline often isn't the one who notices or gets blamed. Stewardship closes that loop: you own the contract between the data producer and its consumers.

Accountability also means escalation. You need to know when to raise an alert versus when to fix it locally, who to notify, and how to prevent recurrence. This is the professional layer—treating data reliability like infrastructure reliability.

## Practice

**Problem:** The `job_postings_fact` table feeds a hiring dashboard used by 40+ stakeholders. Suddenly, `salary_year_avg` becomes NULL for 15% of new records, but the pipeline still runs green. No one notices for 3 days because there's no ownership checkpoint.

**Solution:** Add a stewardship layer with monitoring and a documented escalation path.

```sql
-- 1. Create a data quality checkpoint table
CREATE TABLE job_postings_quality_log (
  check_date DATE,
  total_rows_loaded INT,
  null_salary_count INT,
  null_salary_pct DECIMAL(5,2),
  null_location_count INT,
  duplicate_job_ids INT,
  owner_notified BOOLEAN,
  alert_level VARCHAR(10),
  investigation_notes VARCHAR(500)
);

-- 2. Run quality checks after pipeline load
INSERT INTO job_postings_quality_log
SELECT
  CURRENT_DATE as check_date,
  COUNT(*) as total_rows_loaded,
  COUNTIF(salary_year_avg IS NULL) as null_salary_count,
  ROUND(100.0 * COUNTIF(salary_year_avg IS NULL) / COUNT(*), 2) as null_salary_pct,
  COUNTIF(job_location IS NULL) as null_location_count,
  COUNTIF(job_id) - COUNT(DISTINCT job_id) as duplicate_job_ids,
  FALSE as owner_notified,
  CASE
    WHEN COUNTIF(salary_year_avg IS NULL) / COUNT(*) > 0.10 THEN 'CRITICAL'
    WHEN COUNTIF(salary_year_avg IS NULL) / COUNT(*) > 0.05 THEN 'WARNING'
    ELSE 'OK'
  END as alert_level,
  NULL as investigation_notes
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;

-- 3. Escalation trigger: auto-alert if threshold breached
SELECT * FROM job_postings_quality_log
WHERE alert_level IN ('CRITICAL', 'WARNING')
  AND owner_notified = FALSE;
  -- This query should trigger a notification (email, Slack, PagerDuty)
  -- Owner documents root cause and updates investigation_notes
```

## Notes

- **Common mistake:** Running the pipeline and assuming downstream correctness. Ownership means you actively check contract compliance (schema, cardinality, freshness, grain) every time.
- **Escalation clarity matters:** Define three levels—*auto-fix* (missing partition, retry logic), *alert owner* (anomaly needing investigation), *page on-call* (data unavailable, cannot proceed). Blur these at your peril.
- **Adjacent topic:** This connects to data contracts (schema versioning, SLA guarantees) and observability (you can't steward what you don't measure). Also ties to incident post-mortems—stewardship includes blameless analysis of why the check didn't catch a failure.
- **Revisit this:** As your data grows, stewardship scales through automation (Great Expectations, dbt tests, data quality platforms), but the *accountability mindset* doesn't automate. You're training yourself to think like a reliability engineer.
- **One more thing:** Document ownership explicitly. Who owns salary_year_avg? Who owns the escalation path? This shouldn't live in someone's Slack history—it lives in a OWNERS.md or a governance tool.
