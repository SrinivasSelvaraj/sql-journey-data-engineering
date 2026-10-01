---
date: 2026-10-01
phase: reliability
topic: Privacy observability: GDPR and compliance without exposing data
---

# Privacy observability: GDPR and compliance without exposing data

*Quality, reliability and the professional layer*

## Concept

Privacy observability means instrumenting data pipelines to verify GDPR compliance and data handling without needing to inspect the actual sensitive data itself. Instead of logging salary values or full names to debug issues, you log metadata about *how* that data moved: which fields touched which systems, retention timelines, access patterns, and transformation lineage. This is critical because the moment you expose PII or regulated fields in logs, error messages, or monitoring dashboards for troubleshooting, you've already violated compliance—you can't un-see data.

It matters when you're owning a production pipeline, not just building it. A pipeline owner is accountable for what happens to data end-to-end: if a salary column gets accidentally copied to a non-encrypted staging table, or a job location is retained past its retention window, that's on you. Without privacy observability, you discover these problems through audits or breaches, not proactively.

What breaks without it: teams fall into the trap of logging everything for observability (field values, row counts by sensitive dimension, user details in error traces) and then scrambling to retrofit de-identification. Worse, you can't confidently answer "where did this regulated field go?" or "was this data processed according to our retention policy?" under pressure.

## Practice

**Problem:** Your `job_postings_fact` table includes salary data. A downstream team reports that salary averages by location look wrong. Your instinct is to log actual salary values and location names to find the bug. But location data may be regulated under GDPR (especially in the EU), and salary is always sensitive. How do you debug without exposing either?

```sql
-- Observability layer: log metadata, not the data itself
CREATE TABLE pipeline_audit_log (
  run_id STRING,
  pipeline_name STRING,
  step_name STRING,
  table_name STRING,
  field_name STRING,
  field_hash STRING,  -- hash of sensitive value, never the value
  row_count INT,
  min_date DATE,
  max_date DATE,
  data_classification STRING,  -- 'PII', 'SENSITIVE', 'PUBLIC'
  retention_policy STRING,
  processed_at TIMESTAMP
);

-- During pipeline execution, log metadata only
INSERT INTO pipeline_audit_log
SELECT 
  'run_20240115_001' as run_id,
  'salary_aggregation' as pipeline_name,
  'extract' as step_name,
  'job_postings_fact' as table_name,
  'salary_year_avg' as field_name,
  MD5(CAST(salary_year_avg AS STRING)) as field_hash,  -- detectable without exposure
  COUNT(*) as row_count,
  MIN(job_posted_date) as min_date,
  MAX(job_posted_date) as max_date,
  'SENSITIVE' as data_classification,
  '90_days' as retention_policy,
  CURRENT_TIMESTAMP() as processed_at
FROM job_postings_fact
GROUP BY field_hash;

-- Query for debugging: use hashes and counts, never raw values
SELECT 
  field_name,
  field_hash,
  row_count,
  data_classification
FROM pipeline_audit_log
WHERE pipeline_name = 'salary_aggregation' 
  AND processed_at >= CURRENT_DATE() - 1;

-- Separate, access-controlled query for compliance review (audit trail only)
SELECT 
  run_id,
  table_name,
  COUNT(*) as records_processed,
  MIN(min_date) as earliest_record,
  MAX(max_date) as latest_record
FROM pipeline_audit_log
WHERE data_classification IN ('PII', 'SENSITIVE')
GROUP BY run_id, table_name;
```

## Notes

- **Mistake:** Logging error messages with context like `"Failed to aggregate salary for location='Paris'"`. Use error codes and hashes instead: `"Error CODE_AGG_001 for location_hash=abc123"`.
- **Mistake:** Assuming anonymization is observability—you still need to know *if* anonymization happened and to whom. Log the transformation, not the result.
- **Connects to:** Data lineage tools (dbt, Collibra, Atlan) and access control—observability is the evidence layer that proves compliance, access logs are the enforcement layer.
- **Revisit:** Schema classification—you can't do privacy observability well if you don't have a data dictionary marking which fields are PII, SENSITIVE, or PUBLIC. This is foundational.
- **Revisit:** Retention policies as code—don't just document that salary data lives for 90 days; encode it into your pipeline so deletion is automatic and auditable.
