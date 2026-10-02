---
date: 2026-10-02
phase: reliability
topic: Lineage tracking and column-level impact analysis
---

# Lineage tracking and column-level impact analysis

*Quality, reliability and the professional layer*

## Concept

Lineage tracking documents the path data takes from source to consumer—which tables feed which, which transformations run where, and crucially, *which columns are derived from which*. Column-level lineage goes deeper: it answers "if source table X.column_Y changes, what downstream reports break?" Without it, a schema rename, a business logic bug, or a data quality issue in one place silently cascades. You deploy a fix and don't know if three dashboards just broke or if you fixed all the ones that mattered.

This moves you from "I built a pipeline" to "I own the impact of this pipeline." When someone reports a metric discrepancy, you don't guess—you trace the column back through joins, case statements, and window functions to its origin. When you deprecate a data source, you have proof of what depends on it. When you optimize a slow query by changing its join logic, you know exactly which downstream consumers are affected and can alert them before deployment.

## Practice

**Problem:** The `salary_year_avg` column in `job_postings_fact` is currently null for 30% of rows because the source extraction logic treats missing salary data inconsistently. You need to:
1. Document which downstream reports or tables consume this column
2. Show the derivation path (source → transformation → fact table)
3. Create a mechanism to flag impact when the null rate exceeds 20%

**Solution:**

```sql
-- Create lineage tracking table
CREATE TABLE IF NOT EXISTS column_lineage (
  source_system STRING,
  source_table STRING,
  source_column STRING,
  target_table STRING,
  target_column STRING,
  transformation_logic STRING,
  created_at TIMESTAMP,
  owner STRING
);

INSERT INTO column_lineage VALUES
('job_api', 'raw_postings', 'salary', 'job_postings_fact', 'salary_year_avg', 
 'CAST(salary AS DECIMAL) WHERE salary IS NOT NULL', CURRENT_TIMESTAMP, 'data_eng_team');

-- Monitor data quality impact
CREATE TABLE IF NOT EXISTS column_quality_alerts (
  target_table STRING,
  target_column STRING,
  null_rate DECIMAL(5,2),
  alert_threshold DECIMAL(5,2),
  check_time TIMESTAMP,
  status STRING
);

-- Run this after each load
INSERT INTO column_quality_alerts
SELECT 
  'job_postings_fact',
  'salary_year_avg',
  ROUND(100.0 * SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) as null_rate,
  20.0,
  CURRENT_TIMESTAMP,
  CASE 
    WHEN 100.0 * SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) / COUNT(*) > 20.0 
    THEN 'ALERT'
    ELSE 'OK'
  END
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 1 DAY;

-- Query: show me everything downstream of salary_year_avg
SELECT DISTINCT
  cl.target_table,
  cl.target_column,
  d.dashboard_name,
  d.owner as dashboard_owner
FROM column_lineage cl
LEFT JOIN dashboard_dependencies d ON d.table_name = cl.target_table
WHERE cl.source_column = 'salary' 
  AND cl.source_system = 'job_api';
```

## Notes

- **Mistake:** Treating lineage as a one-time documentation task. It must be automated and live—manual lineage graphs rot the moment schema changes happen.
- **Mistake:** Only tracking table-level lineage. A column might flow through 5 transforms, get renamed twice, and land in two different fact tables. Column-level is non-negotiable for impact radius.
- **Adjacent topic:** Data contracts (schema + quality SLAs). Lineage tells you *what depends on what*; contracts enforce *what quality is promised*. Use them together.
- **Adjacent topic:** Reverse lineage (impact radius) vs. forward lineage (origin tracing). Both directions matter—one answers "what breaks if I change this?", the other answers "where did this number come from?"
- **Revisit:** Diff detection on schema changes. If `salary_year_avg` changes type or nullability, that's a breaking change. Lineage tells you who to notify.
