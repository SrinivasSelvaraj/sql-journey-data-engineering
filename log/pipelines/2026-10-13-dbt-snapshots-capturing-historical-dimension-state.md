---
date: 2026-10-13
phase: pipelines
topic: dbt snapshots: capturing historical dimension state
---

# dbt snapshots: capturing historical dimension state

*Pipelines and orchestration*

## Concept

dbt snapshots capture the historical state of slowly-changing dimensions (SCDs) by recording when attributes change and creating effective-dated rows. Without snapshots, dimension updates overwrite prior values, destroying the audit trail needed for historical analysis—you lose the ability to ask "what was the salary range when this job was posted?" or "how many jobs required remote work in Q2?"

Snapshots work by comparing current source data against the last snapshot version, detecting changes, and inserting new rows with `dbt_valid_from` and `dbt_valid_to` timestamps. This SCD Type 2 pattern is essential when dimensions drift over time but you need to preserve lineage and enable time-travel queries. The alternative—storing full history manually or reprocessing all facts—becomes unmaintainable at scale.

Without snapshots, your fact tables join to stale dimension attributes, metrics become inconsistent across reporting periods, and compliance audits fail. Snapshots fail silently when row counts explode due to incorrect unique keys or when valid_to logic breaks during reruns, so idempotent snapshot definitions and explicit `unique_key` configuration are non-negotiable.

## Practice

**Problem**: The `job_postings_fact` table sources from a live jobs API that updates job titles and salary ranges weekly. You need to track what salary range was advertised when each job posted, and report how many active postings offered remote work by week—without losing historical snapshots when the same job record updates.

```sql
{% snapshot job_postings_snapshot %}
  {{
    config(
      target_schema='analytics',
      unique_key='job_id',
      strategy='timestamp',
      updated_at='updated_at',
    )
  }}
  
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_location,
    updated_at
  FROM {{ source('raw_api', 'job_postings') }}
  WHERE updated_at IS NOT NULL

{% endsnapshot %}

-- Usage in facts: join to snapshot to get salary at job_posted_date time
SELECT
  jp.job_id,
  jp.job_posted_date,
  jps.salary_year_avg,
  jps.job_work_from_home,
  CURRENT_DATE AS dbt_load_date
FROM {{ source('raw_api', 'job_postings') }} jp
INNER JOIN {{ ref('job_postings_snapshot') }} jps
  ON jp.job_id = jps.job_id
  AND jp.job_posted_date >= jps.dbt_valid_from
  AND jp.job_posted_date < COALESCE(jps.dbt_valid_to, '2099-12-31')
```

## Notes

- **Unique key must be stable**: `job_id` alone is insufficient if a single job can be posted multiple times or if composite keys (job_id + version) exist; mismatched unique keys create orphaned snapshots and duplicate valid_to rows.
- **Timestamp strategy requires monotonic updates**: if your source system backfills or backdates `updated_at`, snapshots diverge from reality; validate that `updated_at` only moves forward or switch to `check_strategy` for specific columns.
- **Snapshot tables are immutable append-only**: never modify the snapshot directly or rerun with `--full-refresh` casually—you'll lose the dbt_valid_to chain and break downstream fact lineage; plan for snapshot migration as part of schema evolution.
- **Adjacent concern—fact table grain**: ensure facts are keyed at the right temporal grain (per job posting, not per day) so joins to valid_from/valid_to don't create fanouts or cartesian products.
- **Revisit: SCD Type 1 vs Type 2 trade-offs**: not all dimensions need snapshots; Type 1 (overwrite) is simpler for fast-moving attributes like job_location, but Type 2 is mandatory for salary, title, and compliance-tracked fields.
