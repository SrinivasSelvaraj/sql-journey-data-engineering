---
date: 2026-08-22
phase: pipelines
topic: Dynamic DAG generation from metadata tables
---

# Dynamic DAG generation from metadata tables

*Pipelines and orchestration*

## Concept

Dynamic DAG generation means constructing your workflow graph at runtime by reading configuration or metadata tables, rather than hard-coding task definitions in Python. Instead of writing `task_a >> task_b >> task_c` in your DAG file, you query a table that says "run these transformations in this order for these datasets" and programmatically build the graph.

This matters when you have repetitive pipelines across many tables, frequent schema changes, or business logic that lives in databases rather than code. A data warehouse with 50 similar fact tables shouldn't require 50 nearly-identical DAGs. Without dynamic generation, adding a new table means code deployment; with it, you insert a row.

It breaks when you assume the DAG structure is static. Airflow and most orchestrators compile the DAG once at parse time—if your metadata changes mid-run, the scheduler doesn't pick it up until the next parse cycle. You also lose visibility: static DAGs are easier to audit and visualize than ones assembled from database queries. And if your metadata table is inconsistent or missing, your pipeline silently skips work or crashes cryptically.

## Practice

**Problem:** You maintain ETL for multiple job posting sources. Each source needs extraction, validation, and load steps in sequence, but new sources are added monthly. Currently you have one DAG per source; this doesn't scale.

**Solution:** Store source metadata in a table and generate tasks dynamically.

```sql
-- Metadata table defining all job posting sources and their processing order
CREATE TABLE IF NOT EXISTS etl_pipeline_config (
    pipeline_id INT,
    source_name VARCHAR(50),
    task_sequence INT,
    task_type VARCHAR(20),  -- 'extract', 'validate', 'load'
    sql_or_script VARCHAR(500),
    depends_on VARCHAR(50),  -- NULL or previous task_type
    retry_count INT,
    timeout_minutes INT
);

INSERT INTO etl_pipeline_config VALUES
(1, 'linkedin_jobs', 1, 'extract', 'python extract_linkedin.py', NULL, 3, 30),
(1, 'linkedin_jobs', 2, 'validate', 'dbt test -s linkedin_staging', 'extract', 2, 15),
(1, 'linkedin_jobs', 3, 'load', 'INSERT INTO job_postings_fact SELECT * FROM linkedin_staging', 'validate', 1, 45),
(2, 'glassdoor_jobs', 1, 'extract', 'python extract_glassdoor.py', NULL, 3, 40),
(2, 'glassdoor_jobs', 2, 'validate', 'dbt test -s glassdoor_staging', 'extract', 2, 15),
(2, 'glassdoor_jobs', 3, 'load', 'INSERT INTO job_postings_fact SELECT * FROM glassdoor_staging', 'validate', 1, 50);

-- Query to fetch pipeline config for DAG generation
SELECT 
    source_name,
    task_type,
    task_sequence,
    sql_or_script,
    retry_count,
    timeout_minutes
FROM etl_pipeline_config
WHERE pipeline_id = 1
ORDER BY task_sequence;
```

In your Airflow DAG file, query this table and loop to create `BashOperator` or `PythonOperator` tasks, setting dependencies based on `task_sequence` and `depends_on`.

## Notes

- **Metadata-source-of-truth drift:** If you update the config table but forget to restart the Airflow scheduler, the DAG is stale. Always version your configs and make schema changes explicit.
- **Debugging opacity:** When a dynamic DAG fails, the error often points to the query or loop logic, not your actual transformation. Log the generated task graph to JSON or visualize it early.
- **Parsing performance:** Querying metadata at DAG parse time (every 30 seconds by default) can hammer your database. Cache config in Airflow variables or files, or reduce parse frequency for dynamic DAGs.
- **Relates to:** Template variables, parameterized DAGs, and infrastructure-as-code patterns; also touches on data lineage tracking and CI/CD for pipeline configs.
- **Revisit:** Test that tasks fail loudly (explicit exit codes, alerting), can be safely rerun (idempotent loads, incremental logic), and log their intent (what data moved, why, when).
