---
date: 2026-10-13
phase: pipelines
topic: dbt seed: loading static reference data
---

# dbt seed: loading static reference data

*Pipelines and orchestration*

## Concept

A **dbt seed** is a CSV file checked into version control that dbt loads into your data warehouse as a table. It's the mechanism for managing small, static reference data—lookup tables, dimension tables, configurations—that don't change frequently and don't come from a source system. Seeds live in the `seeds/` directory and are materialized via `dbt seed`.

Seeds matter because reference data often needs to exist before your fact tables can join to it, and hardcoding lookups in SQL is brittle. Without seeds, you either manually maintain reference tables (prone to drift), embed logic in multiple places (hard to update), or skip enrichment entirely. A seed becomes your single source of truth: versioned, documented, and reproducible across environments.

Breaks without it: You have a `job_postings_fact` table, but no canonical mapping of `job_title_short` to `job_category`. Team members create different lookup tables locally, tests fail silently, and your dashboards show inconsistent groupings. A seed fixes this by enforcing one authoritative reference layer.

## Practice

**Problem:** You need to enrich `job_postings_fact` with job categories and seniority levels. These mappings are stable and maintained by the data team, not generated from upstream systems.

Create `seeds/job_title_mapping.csv`:
```
job_title_short,job_category,seniority_level
Data Analyst,Analytics,Mid
Senior Data Engineer,Engineering,Senior
Product Manager,Product,Mid
```

Then create `models/staging/stg_job_postings.sql`:
```sql
select
    jp.job_id,
    jp.job_title_short,
    jtm.job_category,
    jtm.seniority_level,
    jp.salary_year_avg,
    jp.job_work_from_home,
    jp.job_posted_date,
    jp.job_location
from {{ ref('job_postings_fact') }} jp
left join {{ ref('job_title_mapping') }} jtm
    on jp.job_title_short = jtm.job_title_short
```

Run `dbt seed` once per environment; the reference table is now queryable and versioned.

## Notes

- **Seeds are not for large tables.** If your reference data exceeds ~100k rows or grows daily, use a dbt source instead. Seeds are for small, hand-curated lookup tables.
- **Seed changes trigger downstream rebuilds.** Modify a seed CSV, run `dbt seed`, and downstream models will rerun. This is good (reproducibility) but means seed edits need review, just like code.
- **CSV encoding matters.** Ensure UTF-8 encoding and consistent delimiters; dbt will fail loudly on parse errors, which is a feature, not a bug.
- **Document seed purpose in YAML.** Add `seeds/schema.yml` with descriptions of each seed and its columns—future you will appreciate it when debugging a stale mapping.
- **Connects to:** dbt sources (external reference data), tests (validate seed integrity), and version control as the enforcement layer for data contracts.
