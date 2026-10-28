---
date: 2026-10-28
phase: pipelines
topic: Task groups and hierarchical organization
---

# Task groups and hierarchical organization

*Pipelines and orchestration*

## Concept

Task groups bundle related tasks into logical units, reducing DAG complexity and making orchestration intent clearer. Instead of a flat list of 50 tasks, you group extraction tasks, transformation tasks, and loading tasks—making dependencies easier to reason about and failures easier to isolate. In Airflow, a TaskGroup acts as a container; in dbt, you use `meta` tags or model selectors; in other tools, explicit grouping patterns organize work.

They matter most when pipelines grow beyond 10–15 tasks. Without grouping, you lose visibility into which stage failed (raw data load? transformation? quality checks?), and parallel execution becomes harder to tune. A grouped pipeline also makes monitoring clearer—you can check "did the bronze layer complete?" rather than scanning 30 individual task statuses. It's especially critical for fail-loudly-and-rerun-safely behavior: a failed extraction task group should block dependent transformation groups, while a failed quality check should trigger only a subset of downstream reruns.

Without hierarchical organization, you also lose the ability to retry whole stages selectively. Flat DAGs force you to either rerun everything or manually hunt for which tasks depend on what—fragile, slow, and error-prone.

## Practice

**Problem**: A job postings pipeline extracts from three sources (LinkedIn, Indeed, Glassdoor), validates each source, unions them into a staging table, applies business logic (salary caps, location standardization), runs quality checks, and loads to the fact table. Currently all 15 tasks sit flat in the DAG. When a single validation fails, operators don't know if it's safe to rerun just that source or if they must restart the entire pipeline.

```sql
-- Organized task structure (pseudocode in Airflow/dbt style):

-- Task Group 1: EXTRACT (parallel, idempotent)
extract_linkedin >> validate_linkedin
extract_indeed >> validate_indeed
extract_glassdoor >> validate_glassdoor

-- Task Group 2: UNION & STAGE (depends on all validations passing)
[validate_linkedin, validate_indeed, validate_glassdoor] >> union_sources >> stage_job_postings

-- Task Group 3: TRANSFORM (business logic, can rerun independently if stage is clean)
stage_job_postings >> normalize_salary >> normalize_location >> enrich_work_from_home

-- Task Group 4: VALIDATE (fail loud—block load if checks fail)
enrich_work_from_home >> dbt_test_salary_not_null
enrich_work_from_home >> dbt_test_location_valid
enrich_work_from_home >> dbt_test_posted_date_not_future

-- Task Group 5: LOAD (only if all validations pass)
[dbt_test_salary_not_null, dbt_test_location_valid, dbt_test_posted_date_not_future] >> load_fact_table

-- In dbt, this maps to:
-- models/staging/stg_job_postings.sql (union of three sources, tests in dbt_project.yml)
-- models/marts/job_postings_fact.sql (business logic, depends on stg_job_postings)
-- tests/ folder (one test per critical column)
```

This structure allows: rerunning a single source extraction; rerunning all transformations if a validation fails midway; clear identification of which stage broke; and safe reruns without data duplication.

## Notes

- **Common mistake**: Grouping by tool rather than by logical data stage. Don't create a "Python tasks" group and a "SQL tasks" group; create "extraction," "validation," and "load" groups. Tool is an implementation detail.

- **Adjacent topic**: Depends on clear idempotency contracts—each task group must be safely rerunnable without side effects. Task groups don't fix non-idempotent logic; they expose it faster.

- **Connection to fail loudly**: Grouped structure makes test failures scream louder. A validation task group that fails blocks the entire load group, preventing silent downstream corruption. Flat DAGs let bad data slip through because downstream tasks don't always fail cleanly.

- **Reruns and backfills**: Hierarchical organization is essential for selective backfills. You can rerun "transform only" without touching extraction, or "validate and load" without re-extracting—only possible if groups are cleanly separated.

- **Revisit when**: Your DAG exceeds ~12 tasks, you see operators manually retrying subsets, or monitoring dashboards become hard to scan. Also revisit after adding new data sources or quality checks—grouping boundaries may need adjustment.
