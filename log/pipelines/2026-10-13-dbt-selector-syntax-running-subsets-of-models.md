---
date: 2026-10-13
phase: pipelines
topic: dbt selector syntax: running subsets of models
---

# dbt selector syntax: running subsets of models

*Pipelines and orchestration*

## Concept

dbt selectors let you run specific subsets of models instead of entire projects, which is critical when your DAG grows beyond a handful of tables. Without selectors, every `dbt run` rebuilds everything—wasteful in development, dangerous in production if you only want to refresh downstream tables after fixing one model. Selectors use graph syntax (`+`, `@`) and tag/path matching to target exactly what needs to run.

The most common patterns are `dbt run -s tag:daily` (by tag), `dbt run -s path/to/models` (by directory), `dbt run -s model_name+` (model plus all downstream), and `dbt run -s +model_name` (all upstream plus model). This becomes indispensable when you have hundreds of models and only certain ones changed, or when you need to rebuild a fact table and everything downstream without touching unrelated branches.

Without selector discipline, teams either waste compute on full runs or accidentally miss dependent models, breaking downstream reports. Proper selector use lets you fail fast, rerun only what's necessary, and keep DAGs debuggable.

## Practice

**Problem:** You have `stg_job_postings` feeding `job_postings_fact`, which feeds three reporting views: `rpt_salary_analysis`, `rpt_location_heat_map`, and `rpt_remote_jobs`. You discovered a bug in `stg_job_postings` and fixed it. You want to rebuild the staging model and all models that depend on it, but *not* unrelated models in the project.

```sql
-- In dbt_project.yml, tag your models:
models:
  my_project:
    staging:
      +tags: ["daily"]
    marts:
      fact:
        +tags: ["daily", "core_fact"]
      reporting:
        +tags: ["daily"]

-- From the CLI, run the staging model and everything downstream:
dbt run -s stg_job_postings+

-- Or more explicitly, run staging + all dependent models:
dbt run -s +stg_job_postings job_postings_fact rpt_salary_analysis rpt_location_heat_map rpt_remote_jobs

-- Or use tags if all downstream are tagged consistently:
dbt run -s tag:daily
```

## Notes

- **Common mistake:** Forgetting `+` and `-` directives. `dbt run -s job_postings_fact` runs only that model; `+job_postings_fact` includes all parents; `job_postings_fact+` includes all children. Always know which direction you're going.
- **Tag early, tag often:** Selectors are most powerful with a consistent tagging strategy (e.g., `daily`, `weekly`, `core_fact`, `pii`). Without tags, you'll repeat long selector strings everywhere.
- **Union and intersection:** Use commas for union (`-s model_a model_b`) and set operations like `dbt run -s tag:daily,tag:core_fact` for intersection; this matters when rerunning complex subgraphs.
- **Connects to:** model dependencies (the graph itself), state selectors (`state:new` after `dbt parse`), and orchestration tools (Airflow/dbt Cloud use selectors to define job boundaries).
- **Revisit:** State-based selection (`dbt run -s state:modified`) becomes essential in CI/CD pipelines where you only want to rebuild changed models; combine it with selectors for surgical reruns.
