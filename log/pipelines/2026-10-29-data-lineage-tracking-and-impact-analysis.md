---
date: 2026-10-29
phase: pipelines
topic: Data lineage tracking and impact analysis
---

# Data lineage tracking and impact analysis

*Pipelines and orchestration*

## Concept

Data lineage tracking maps the journey of data from source to consumer—which tables feed which transformations, which jobs depend on which outputs. Without it, when a dashboard breaks or a metric disagrees with last month, you're debugging blind: you don't know if the problem is upstream (bad source data), in the pipeline (broken logic), or downstream (incorrect consumption). Impact analysis answers the inverse: if I change this table, what else breaks? This matters at scale because one missing column or one silent NULL can propagate through ten jobs before surfacing as a user complaint.

Breaking without it is inevitable. A schema change in a source system silently fails a join; a job runs late, cascading delays through dependent jobs that don't know why they're waiting; a metric calculation changes and no one realizes which dashboards are now stale. Teams waste hours tracing through logs and configurations to answer "where did this data come from?" Data lineage makes these relationships explicit and queryable.

## Practice

**Problem:** You maintain the `job_postings_fact` table. The salary data comes from a `raw_job_postings` source, and three downstream dashboards consume it: recruiting metrics, market analysis, and compensation benchmarking. When a data quality issue is discovered in salary values (many NULLs introduced last Tuesday), you need to: (1) identify what feeds this table, (2) identify what depends on it, (3) understand the time window of bad data, and (4) rebuild confidently.

```sql
-- 1. Document lineage: create metadata tables
CREATE TABLE IF NOT EXISTS lineage_source_to_table (
  source_name STRING,
  source_type STRING,
  target_table STRING,
  job_name STRING,
  last_run_time TIMESTAMP,
  row_count BIGINT
);

-- 2. Document lineage: table to consumer
CREATE TABLE IF NOT EXISTS lineage_table_to_consumer (
  source_table STRING,
  consumer_dashboard_or_job STRING,
  consumer_type STRING,
  refresh_frequency STRING,
  last_validated_time TIMESTAMP
);

-- 3. On pipeline completion, insert lineage records
INSERT INTO lineage_source_to_table 
VALUES ('raw_job_postings', 'database', 'job_postings_fact', 'etl_job_postings', CURRENT_TIMESTAMP(), (SELECT COUNT(*) FROM job_postings_fact));

INSERT INTO lineage_table_to_consumer 
VALUES ('job_postings_fact', 'recruiting_metrics_dashboard', 'dashboard', 'daily', CURRENT_TIMESTAMP());
INSERT INTO lineage_table_to_consumer 
VALUES ('job_postings_fact', 'market_analysis_dashboard', 'dashboard', 'daily', CURRENT_TIMESTAMP());
INSERT INTO lineage_table_to_consumer 
VALUES ('job_postings_fact', 'compensation_benchmarking', 'dashboard', 'weekly', CURRENT_TIMESTAMP());

-- 4. Query impact: if salary_year_avg is broken, what's affected?
SELECT DISTINCT consumer_dashboard_or_job, consumer_type 
FROM lineage_table_to_consumer 
WHERE source_table = 'job_postings_fact' 
ORDER BY consumer_type;

-- 5. Query source: what feeds job_postings_fact and when was it last loaded?
SELECT source_name, last_run_time, row_count 
FROM lineage_source_to_table 
WHERE target_table = 'job_postings_fact' 
ORDER BY last_run_time DESC 
LIMIT 1;
```

## Notes

- **Mistake:** Assuming lineage is "nice to have." It's not—it's how you survive incidents. Build it into your pipeline orchestration from day one, not after the first outage.
- **Mistake:** Tracking lineage in Confluence or a spreadsheet. It goes stale immediately. Lineage must be queryable metadata, updated automatically by jobs.
- **Connection:** This pairs tightly with idempotent pipeline design; without lineage you can't safely rerun jobs because you don't know what downstream consumers will see the old data.
- **Connection:** Lineage feeds alerting: if a source job fails, automatically alert consumers; if a table's row count drops 50%, flag dependent dashboards.
- **Revisit:** Tools like dbt, Airflow, and Dataform provide built-in lineage; understand your orchestrator's lineage capabilities and how to query them before building custom metadata tables.
