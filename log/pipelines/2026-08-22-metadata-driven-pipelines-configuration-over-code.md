---
date: 2026-08-22
phase: pipelines
topic: Metadata-driven pipelines: configuration over code
---

# Metadata-driven pipelines: configuration over code

*Pipelines and orchestration*

## Concept

Metadata-driven pipelines externalize pipeline logic into declarative configuration (YAML, JSON, databases) rather than embedding it in code. Instead of writing a new Python script for each data source, you define table schemas, column mappings, validation rules, and transformation logic in configuration files. The pipeline engine reads this metadata and executes consistently.

This matters because data engineering involves repetitive patterns: extract from source A, validate columns, deduplicate on key X, load to warehouse. Without metadata-driven design, you rewrite these patterns for every new table, creating brittle code that's hard to maintain and audit. When a source changes its schema or a business rule shifts, you're modifying code, re-testing, and redeploying. Metadata-driven systems let non-engineers update pipelines and make changes auditable and reversible.

It breaks without this: validation rules live scattered across five SQL scripts and one Python function, making it impossible to know what's actually being checked. New tables require copy-pasting boilerplate. When job_postings_fact needs a new NOT NULL constraint, you hunt through three files. Errors are cryptic because the pipeline can't explain *why* a row was rejected.

## Practice

**Problem:** You need to load job_postings_fact daily from a CSV source. Different teams require different validation rules: Finance needs salary_year_avg ≥ 0 and job_posted_date within 90 days; Recruiting needs job_title_short non-null and job_location populated. If validation fails, the pipeline should log which rule failed and which rows violated it, then halt before loading bad data.

```sql
-- Metadata table: defines table and column-level rules
CREATE TABLE pipeline_config (
  table_name VARCHAR,
  column_name VARCHAR,
  rule_type VARCHAR,
  rule_value VARCHAR,
  severity VARCHAR,
  team VARCHAR
);

INSERT INTO pipeline_config VALUES
  ('job_postings_fact', 'salary_year_avg', 'min_value', '0', 'error', 'finance'),
  ('job_postings_fact', 'job_posted_date', 'recency_days', '90', 'error', 'finance'),
  ('job_postings_fact', 'job_title_short', 'not_null', 'true', 'error', 'recruiting'),
  ('job_postings_fact', 'job_location', 'not_null', 'true', 'error', 'recruiting');

-- Validation query: reads config and applies rules dynamically
WITH staged_data AS (
  SELECT * FROM job_postings_fact_staging
),
validation_results AS (
  SELECT 
    job_id,
    CASE 
      WHEN (SELECT rule_value FROM pipeline_config WHERE table_name='job_postings_fact' 
            AND column_name='salary_year_avg' AND rule_type='min_value')::INT > 0
           AND salary_year_avg < 0 
        THEN 'salary_year_avg < 0'
      WHEN (SELECT rule_value FROM pipeline_config WHERE table_name='job_postings_fact' 
            AND column_name='job_posted_date' AND rule_type='recency_days')::INT > 0
           AND job_posted_date < CURRENT_DATE - INTERVAL '90 days'
        THEN 'job_posted_date > 90 days old'
      WHEN job_title_short IS NULL 
        THEN 'job_title_short is null'
      WHEN job_location IS NULL 
        THEN 'job_location is null'
      ELSE 'pass'
    END AS validation_status
  FROM staged_data
)
INSERT INTO pipeline_validation_log (table_name, job_id, failure_reason, check_timestamp)
SELECT 'job_postings_fact', job_id, validation_status, NOW()
FROM validation_results
WHERE validation_status != 'pass';

-- Pipeline halts if errors exist
SELECT CASE WHEN COUNT(*) > 0 THEN RAISE EXCEPTION 'Validation failed: % rows rejected', COUNT(*)
            ELSE 'All validations passed' END
FROM pipeline_validation_log
WHERE table_name = 'job_postings_fact' AND check_timestamp = CURRENT_DATE;
```

## Notes

- **Common mistake:** Storing metadata in code comments or loose spreadsheets instead of queryable tables. Configuration must be versioned, auditable, and queryable so you can ask "which rules apply to salary_year_avg?" and trace changes.
- **Adjacent topic:** Data contracts (schema, freshness, cardinality SLAs) are the next layer—metadata defines not just how to transform, but what you *promise* downstream consumers about the data.
- **Revisit:** Templating engines (Jinja2, dbt macros) let you parameterize SQL itself; combine with metadata to generate entire DAGs from config.
- **Mistake:** Over-engineering from day one. Start with YAML for one table's rules, prove it works, then scale. Premature generalization leads to unmaintai
