---
date: 2026-10-29
phase: pipelines
topic: Trigger rules and downstream task handling
---

# Trigger rules and downstream task handling

*Pipelines and orchestration*

## Concept

Trigger rules determine when a downstream task should execute based on upstream task state—success, failure, skipped, or custom conditions. Without explicit trigger rules, pipelines either block on all upstream failures (too fragile) or ignore them (masking real problems). The right rule set lets critical transformations proceed when safe, halts when dangerous, and surfaces failures clearly instead of cascading silently through the DAG.

Trigger rules matter most at pipeline junctures: after data quality checks, before final loads, and around optional enrichment steps. A data quality job failing should block a production load but not a downstream reporting layer that can work with yesterday's data. A late-arriving dimension table might justify a retry-and-continue rule rather than pipeline death. Without this intentionality, you either restart entire pipelines on minor hiccups or ship corrupt data because intermediate failures went unnoticed.

## Practice

**Problem:** Your `job_postings_fact` load depends on upstream tasks: `extract_postings` (critical—must succeed), `enrich_locations` (optional—data quality check that may fail), and `validate_salary_schema` (critical). You need the load to proceed only if extraction and schema validation pass, but succeed even if location enrichment fails. Design the trigger rule logic.

```sql
-- Orchestration layer (pseudo-code / Airflow-style)
-- task: load_job_postings_fact

load_job_postings_fact = PostgresOperator(
    task_id='load_job_postings_fact',
    sql='''
    INSERT INTO job_postings_fact 
    (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
    SELECT 
        jp.job_id,
        jp.job_title_short,
        jp.salary_year_avg,
        jp.job_work_from_home,
        jp.job_posted_date,
        COALESCE(el.location, jp.location_raw) AS job_location
    FROM staging.job_postings jp
    LEFT JOIN staging.enriched_locations el ON jp.job_id = el.job_id
    WHERE jp.extraction_id = (SELECT MAX(extraction_id) FROM staging.job_postings)
    ''',
    trigger_rule='none_failed_min_one_success',  -- proceed if ≥1 upstream succeeded & none failed
    depends_on_past=False,
)

# Explicit dependency chain:
extract_postings >> validate_salary_schema >> load_job_postings_fact
enrich_locations >> load_job_postings_fact  -- optional; LEFT JOIN handles missing data

# Trigger breakdown:
# extract_postings: success required (hard dependency)
# validate_salary_schema: success required (hard dependency)
# enrich_locations: can fail without blocking load (soft dependency via trigger rule)
```

## Notes

- **Trigger rule scope:** `all_success` (default—strict), `all_failed`, `one_failed`, `none_failed_min_one_success` (permissive), `none_skipped` (skip-aware). Choose based on whether downstream can tolerate upstream degradation.
- **Common mistake:** Using `all_success` everywhere then wondering why a single check failure kills the entire pipeline. Separate critical path (strict) from optional enrichment (permissive).
- **Upstream state explosion:** A skipped task is neither success nor failure in most rules. Track `skipped` explicitly if you have conditional branching; use `none_skipped` only when skipped tasks indicate a real problem.
- **Adjacent: SLAs and alerting.** Trigger rules control *flow*; SLAs + sensors control *timing* and *retry loops*. A task may succeed with `none_failed` but still alert if it took 10x longer than expected.
- **Revisit:** Combine with data quality gates—enrich_locations failing should log *why* (schema mismatch, API down, data stale?) so you know whether to retry or accept degraded enrichment.
