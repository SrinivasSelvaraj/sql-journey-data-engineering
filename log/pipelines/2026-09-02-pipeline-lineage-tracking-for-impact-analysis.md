---
date: 2026-09-02
phase: pipelines
topic: Pipeline lineage tracking for impact analysis
---

# Pipeline lineage tracking for impact analysis

*Pipelines and orchestration*

## Concept

Pipeline lineage tracking documents the complete flow of data from source to destination, capturing which datasets feed into which transformations and which downstream consumers depend on each stage. Without lineage, a breaking change in an upstream source becomes invisible—you don't know which reports, models, or dashboards are affected until users complain. This matters most when a source schema changes, a transformation logic bug is discovered retroactively, or you need to roll back a week's worth of processing.

Lineage enables impact analysis: before deploying a schema change to `job_postings_fact`, you query the lineage graph to see that three dashboard queries and a machine learning feature pipeline consume `salary_year_avg`. You can then coordinate the rollout or detect incompatibilities early. Without it, you're flying blind—changes propagate silently through the system, creating cascading failures that are expensive to debug and debug.

## Practice

**Problem:** You discover that `job_postings_fact.salary_year_avg` will be NULL for a newly ingested source starting tomorrow. You need to identify all queries that assume this column is non-NULL, along with their owners and downstream dependencies, before the data arrives.

```sql
-- Track lineage by capturing query dependencies
CREATE TABLE IF NOT EXISTS lineage_log (
  source_table STRING,
  source_column STRING,
  target_table STRING,
  target_column STRING,
  job_name STRING,
  job_owner STRING,
  last_run TIMESTAMP,
  query_hash STRING
);

-- Insert lineage entry when a pipeline job runs
INSERT INTO lineage_log VALUES
  ('raw.job_postings', 'salary', 'analytics.job_postings_fact', 'salary_year_avg', 'daily_etl_job', 'data_eng', CURRENT_TIMESTAMP(), MD5('SELECT salary FROM raw.job_postings')),
  ('analytics.job_postings_fact', 'salary_year_avg', 'dashboards.compensation_report', NULL, 'daily_dashboard_refresh', 'analytics', CURRENT_TIMESTAMP(), MD5('SELECT AVG(salary_year_avg) FROM job_postings_fact')),
  ('analytics.job_postings_fact', 'salary_year_avg', 'ml.salary_predictor_features', NULL, 'weekly_feature_build', 'ml_platform', CURRENT_TIMESTAMP(), MD5('SELECT * FROM job_postings_fact'));

-- Query impact analysis: who depends on salary_year_avg?
SELECT DISTINCT
  target_table,
  job_name,
  job_owner,
  COUNT(*) as column_dependencies
FROM lineage_log
WHERE source_table = 'analytics.job_postings_fact'
  AND source_column = 'salary_year_avg'
GROUP BY target_table, job_name, job_owner
ORDER BY job_owner;
```

## Notes

- **Capture at execution time, not code review time:** Parse actual query logs or use hooks in your orchestrator (Airflow operators, dbt metadata) to record which assets touched which columns. Static analysis of code misses dynamic queries and conditional branches.

- **Distinguish column-level from table-level lineage:** Knowing that `job_postings_fact` feeds into a dashboard is useful; knowing that only `salary_year_avg` and `job_title_short` are used narrows impact and may unblock a deployment of changes to other columns.

- **Connects to data contracts and schema governance:** Lineage makes data contracts enforceable—you can programmatically prevent breaking changes to columns that have downstream dependencies, raising an error before deployment.

- **Common mistake: forgetting indirect consumers:** A model built on a view that depends on `job_postings_fact` is still a consumer. If you only track direct dependencies, you miss it. Use recursive queries or graph traversal to capture transitive lineage.

- **Revisit when debugging production incidents:** When `job_postings_fact` stops updating, lineage tells you which jobs to check first and which teams to notify—it transforms a black box into a known dependency map.
