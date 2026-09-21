---
date: 2026-09-21
phase: pipelines
topic: Accumulating mode vs discarding mode for results
---

# Accumulating mode vs discarding mode for results

*Pipelines and orchestration*

## Concept

**Accumulating mode** retains all historical results in your pipeline's result set or table, building a complete audit trail. **Discarding mode** overwrites or discards prior results, keeping only the latest state. The choice determines whether your pipeline is reversible and explainable when failures occur.

This distinction matters most at orchestration boundaries—where one pipeline hands results to the next. In accumulating mode, if a downstream job fails partway through, you can rerun it against the same input snapshot without re-executing the upstream pipeline. In discarding mode, you've already lost the prior state, forcing a full re-run or leaving you unable to recover. Accumulating mode also enables root-cause analysis: you can inspect exactly which input changed between runs and trace its effect forward.

Without explicit mode choice, pipelines become fragile. A crash mid-process corrupts state (in discarding mode) or leaves dangling, incomplete snapshots (in accumulating mode). Fail-loud, rerun-safe pipelines must choose their mode deliberately and codify it in table structure or naming convention.

## Practice

**Problem:** Your `job_postings_fact` table receives daily batch updates. Some days a data quality check fails mid-load, leaving 50% of new records inserted. On retry, you need to know which records were already loaded and which are new, without scanning raw logs or re-running the entire extraction.

**Solution (Accumulating Mode):**

```sql
-- Add a load_id and dbt_loaded_at to track which pipeline run produced each row
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR,
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR,
    load_id INT,           -- batch run identifier
    dbt_loaded_at TIMESTAMP,  -- when this row entered the table
    PRIMARY KEY (job_id, load_id)  -- allows same job in multiple loads
);

-- On retry: only insert records for the current load_id that aren't already present
INSERT INTO job_postings_fact
SELECT 
    job_id, job_title_short, salary_year_avg, job_work_from_home, 
    job_posted_date, job_location,
    123 as load_id,  -- today's batch run
    CURRENT_TIMESTAMP as dbt_loaded_at
FROM staging.job_postings_raw
WHERE job_id NOT IN (SELECT job_id FROM job_postings_fact WHERE load_id = 123)
  AND quality_check_passed = TRUE;
```

This guarantees idempotency: rerunning load_id 123 never duplicates rows, and you retain the historical record of all loads.

## Notes

- **Confuse mode with idempotency:** Accumulating mode enables idempotency but doesn't guarantee it—you must also use unique constraints or merge logic to prevent duplicates on retry.
- **Dimension vs fact tables:** Slowly changing dimensions (SCD Type 2) naturally use accumulating mode; fact tables often use discarding mode but need explicit retry logic. Choose based on your rerun strategy, not table type.
- **Load IDs and run timestamps** are your safety net—always include them. They answer "was this already processed?" instantly, without scanning millions of rows.
- **Discarding mode is valid** when results are truly ephemeral (e.g., hourly aggregates fed into a rolling window) and you control the full pipeline end-to-end with deterministic re-execution.
- **Related:** staging tables, idempotent merges, dbt `on_schema_change`, incremental models with `unique_key`, and audit columns—all reinforce this pattern.
