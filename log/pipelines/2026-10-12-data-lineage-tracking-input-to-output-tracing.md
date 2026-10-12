---
date: 2026-10-12
phase: pipelines
topic: Data lineage tracking: input to output tracing
---

# Data lineage tracking: input to output tracing

*Pipelines and orchestration*

## Concept

Data lineage tracking maps how data flows from source systems through transformations to final outputs. It answers: "Where did this value come from?" and "What will break if I change this upstream table?" Without it, a single bug in an early transformation silently corrupts downstream reports, and you waste hours tracing root causes backward through ten interdependent jobs.

In orchestrated pipelines, lineage becomes critical infrastructure. When a job fails, you need to know instantly which downstream consumers are blocked and which upstream sources may be stale. Lineage also enables safe reruns—you can replay only affected branches without rebuilding the entire DAG, reducing recovery time from hours to minutes.

Breaks without it: orphaned transformations (jobs running with no downstream consumer), silent data quality drift (a schema change propagates undetected), and impossible debugging (a salary figure is wrong; is it the source feed, the currency conversion, or the aggregation?).

## Practice

**Problem:** Your `job_postings_fact` table has a column `salary_year_avg` that feeds three downstream jobs: a dashboard, an ML model, and an archive. A new ETL job adds a `salary_outlier_flag` column. You need to track: (1) which jobs depend on salary data, (2) what happens to them if salary ingestion fails, (3) whether the new flag is derived or sourced.

```sql
-- Lineage tracking schema
CREATE TABLE IF NOT EXISTS pipeline_lineage (
  lineage_id INT PRIMARY KEY AUTO_INCREMENT,
  source_table VARCHAR(255),
  source_column VARCHAR(255),
  target_job VARCHAR(255),
  target_table VARCHAR(255),
  transformation_type ENUM('direct_copy', 'derived', 'aggregated', 'joined'),
  depends_on_freshness BOOLEAN,
  critical_for_downstream BOOLEAN,
  documented_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Register lineage for job_postings_fact → downstream consumers
INSERT INTO pipeline_lineage 
  (source_table, source_column, target_job, target_table, transformation_type, depends_on_freshness, critical_for_downstream)
VALUES
  ('job_postings_fact', 'salary_year_avg', 'salary_report_daily', 'salary_dashboard_fact', 'direct_copy', TRUE, TRUE),
  ('job_postings_fact', 'salary_year_avg', 'ml_salary_predict', 'model_training_input', 'derived', TRUE, TRUE),
  ('job_postings_fact', 'job_id,job_title_short,job_location', 'archive_job_catalog', 'job_archive', 'direct_copy', FALSE, FALSE),
  ('job_postings_fact', 'salary_year_avg', 'job_postings_fact', 'salary_outlier_flag', 'derived', TRUE, FALSE);

-- Query to find blast radius: what breaks if job_postings_fact fails?
SELECT DISTINCT target_job, target_table, critical_for_downstream
FROM pipeline_lineage
WHERE source_table = 'job_postings_fact' AND critical_for_downstream = TRUE;

-- Query to audit: is salary_outlier_flag properly sourced?
SELECT source_table, source_column, transformation_type
FROM pipeline_lineage
WHERE target_table = 'job_postings_fact' AND target_table LIKE '%salary%';
```

## Notes

- **Common mistake:** Tracking lineage in documentation (Wiki, Confluence) instead of queryable metadata. By the time a critical failure hits, your docs are stale. Embed lineage as first-class schema objects.
- **Adjacent topics:** Data contracts (define what each consumer expects from a table), observability/monitoring (alert when a dependency is stale), and DAG visualization tools (Airflow, dbt) that auto-generate lineage from code.
- **Rerun safety:** Lineage tells you which jobs to replay atomically. Without it, you either replay everything (expensive) or skip critical jobs (data inconsistency).
- **Schema evolution risk:** When you add/drop/rename columns in `job_postings_fact`, lineage queries tell you which downstream jobs will break before deployment.
- **Revisit:** How to auto-generate lineage from SQL parsing (dbt's `manifest.json`, or custom parsers) rather than manual registration—this scales to 100+ jobs.
