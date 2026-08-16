---
date: 2026-08-16
phase: reliability
topic: Data lineage and impact analysis
---

# Data lineage and impact analysis

*Quality, reliability and the professional layer*

## Concept

Data lineage is the complete map of where data comes from, how it transforms, and where it flows downstream—the "ancestry" of every value in your warehouse. Impact analysis is the inverse: understanding what breaks when a source changes, a field is removed, or a calculation is corrected. Without lineage, you operate blind; when a metric suddenly shifts, you can't trace whether the issue is upstream (bad ETL), in the transformation (logic error), or downstream (misconfigured dashboard). In mature organizations, lineage isn't optional documentation—it's the foundation of ownership. You own a pipeline not when you write it, but when you can confidently answer: "If we change the job_posted_date calculation, which reports fail and why?"

Lineage becomes non-negotiable at scale. Early-stage pipelines often have implicit lineage: everyone remembers that salary_year_avg comes from a web scrape cleaned in Python, then loaded via dbt. But that knowledge lives in one person's head. Six months later, when that person is unavailable and salary numbers look wrong, no one can trace the issue back through three data sources and four transformation layers. Impact analysis prevents cascading failures: you catch that removing job_work_from_home breaks five downstream dashboards *before* you remove it, not after.

## Practice

**Problem:** Your analytics team discovers that job_postings_fact.salary_year_avg has been null for 25% of records posted in the last week. You need to identify which downstream reports and ML models depend on this field, whether they have fallback logic, and what users you need to notify immediately.

```sql
-- Build a lineage map: trace salary_year_avg upstream and downstream
-- Upstream: which source tables and transformations feed this field?
-- Assume a dbt project with stg_job_postings and raw_postings_api

SELECT 
  'upstream' AS lineage_direction,
  'job_postings_fact.salary_year_avg' AS target_column,
  'stg_job_postings.salary_year_avg' AS source_column,
  'dbt model: stg_job_postings' AS transform_step,
  'COALESCE(raw_postings_api.salary, industry_salary_lookup.avg_salary)' AS logic
UNION ALL
SELECT 
  'upstream',
  'job_postings_fact.salary_year_avg',
  'raw_postings_api.salary',
  'API ingestion job (airflow dag: fetch_postings)',
  'Direct column from vendor API'
UNION ALL
-- Downstream: which tables and reports query this field?
SELECT 
  'downstream' AS lineage_direction,
  'job_postings_fact.salary_year_avg' AS target_column,
  'salary_trend_report.avg_salary_by_title' AS dependent_object,
  'Looker dashboard: Compensation Trends',
  'GROUP BY job_title_short; filters nulls with COALESCE(salary_year_avg, 0)'
UNION ALL
SELECT 
  'downstream',
  'job_postings_fact.salary_year_avg',
  'ml_salary_prediction.training_data',
  'ML pipeline: salary_predictor (retrains daily)',
  'Feature: salary is central to model; nulls removed in preprocessing'
ORDER BY lineage_direction, source_column;
```

This query (or metadata maintained in a tool like Collibra, Lineage, or dbt artifacts) immediately tells you: the salary field depends on API quality and a lookup table, and two critical systems downstream will break or degrade if nulls aren't handled. You can now prioritize: fix the API connector, add monitoring to the lookup join, and alert the Looker and ML teams before they see cascading failures.

## Notes

- **Lineage without automation is theater**: Manual documentation falls stale within weeks. Invest in tools (dbt exposures, OpenLineage, or data catalog platforms) that derive lineage from code and query logs, not from spreadsheets.
- **The 80/20 trap**: You don't need perfect lineage for everything—focus on high-impact paths first. Start with fact tables and critical metrics, then expand. Complete lineage across 200 tables is less useful than reliable lineage across your 20 most-used datasets.
- **Impact analysis needs test coverage**: Lineage shows you what *could* break; tests show you what *does*. A downstream report might have `COALESCE(salary, 0)` that masks nulls silently. Pair lineage with data quality rules and schema tests on dependencies.
- **Connects to**: dbt exposures and artifact parsing, metadata management, observability and monitoring (alerts when lineage assumptions are violated), and change management workflows (version control + deployment reviews).
- **Revisit quarterly**: As pipelines evolve, lineage maps decay. Schedule reviews to catch dead endpoints (dashboards deleted but lineage not updated) and hidden dependencies (someone built a direct SQL query against a staging table instead of using the public layer).
