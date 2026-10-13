---
date: 2026-10-13
phase: pipelines
topic: dbt slim CI: only building changed models and tests
---

# dbt slim CI: only building changed models and tests

*Pipelines and orchestration*

## Concept

dbt slim CI uses the `state:modified` selector to run only the models and tests that have changed since the last successful dbt run, rather than rebuilding your entire DAG. This dramatically speeds up CI pipelines—from 45 minutes to 2 minutes in typical projects—by skipping unchanged upstream models and their dependents unless they're explicitly affected by a schema or logic change.

The mechanism requires storing a `manifest.json` from your production run and comparing it against the current branch's manifest. dbt identifies modified models by detecting changes in their SQL code, YAML definitions, or dependencies. Without slim CI, every commit triggers a full rebuild, wasting compute resources and delaying feedback. This becomes critical as your project scales: a 500-model warehouse makes full rebuilds prohibitively expensive.

When slim CI breaks, it's usually because the state artifact (the production manifest) is stale, missing, or from a different version of dbt than your current run. The result is either false positives (rebuilding unchanged models) or false negatives (missing affected downstream tests). Proper state management is non-negotiable for reliable lean pipelines.

## Practice

**Problem:** Your `job_postings_fact` table includes a `job_posted_date` column. A colleague modifies the upstream source's date formatting logic. You need to rebuild only the affected models and their downstream dependents, plus all tests touching those models, without rebuilding unrelated dimension tables.

```sql
-- dbt_project.yml or CI command
dbt build --select state:modified+ --state ./artifacts --manifest ./artifacts/manifest.json

-- This runs:
-- 1. The upstream source/model that changed (e.g., stg_jobs)
-- 2. job_postings_fact (depends on modified upstream)
-- 3. All tests on job_postings_fact and downstream models
-- 4. Any downstream models consuming job_postings_fact
-- 
-- It skips:
-- job_dim, company_dim, and all their tests (unrelated)
```

## Notes

- **Artifact stale risk:** If your state manifest is >24 hours old or from a different dbt version, slim CI silently misses changes. Always fetch the latest production manifest in CI before running `dbt build --state`.
- **Test selection subtlety:** `state:modified+` includes downstream tests, but attached tests on unchanged models won't run. Use `state:modified+ test_name:*` if you need all tests on modified models.
- **Connects to:** incremental models (often paired with slim CI for maximum speed), dbt Cloud's "defer to production" feature (safer alternative), and `dbt parse` for fast manifest generation.
- **Common failure:** Running slim CI without storing/retrieving the state artifact—it silently falls back to full builds. Always version-control or cache your production manifest.
- **Revisit:** How `dbt docs generate` interacts with slim CI (must run full parse for accurate lineage), and debugging why a model unexpectedly appears in `state:modified` (often hidden dependency changes in YAML configs).
