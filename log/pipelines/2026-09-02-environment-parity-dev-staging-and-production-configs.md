---
date: 2026-09-02
phase: pipelines
topic: Environment parity: dev, staging and production configs
---

# Environment parity: dev, staging and production configs

*Pipelines and orchestration*

## Concept

Environment parity means dev, staging, and production have identical configurations for data pipelines—same schemas, same data types, same partition strategies, same retry logic, same resource limits. Without it, a pipeline that passes all local tests fails mysteriously in production because the table schema differs by one nullable column, or the staging database has a different collation, or the prod warehouse enforces stricter timeout rules.

This matters most when you're building automation that should "fail loudly": if your dev environment silently coerces a string to a timestamp but production rejects it, you've masked a real data quality problem. Parity forces you to catch these issues early. It also matters for rerunning safely—if staging uses truncate-and-reload but prod uses upsert logic, a backfill that worked in staging will corrupt production.

Without environment parity, you spend hours debugging "it worked in dev" issues instead of shipping. You also create false confidence: a green test run doesn't actually mean the pipeline will survive production traffic, skewed data distributions, or schema evolution.

## Practice

**Problem:** You have a fact table for job postings. In dev, `salary_year_avg` is nullable DECIMAL(10,2). Your pipeline calculates aggregates assuming nulls are zeros. In staging, someone changed the column to non-nullable INTEGER to save space. Your test suite passes everywhere because it uses small datasets, but production fails on a null salary record with a type mismatch, and your backfill logic breaks because it can't insert nulls.

**Solution:** Define schemas in code (not via manual DDL) and apply them identically across all environments:

```sql
-- Define once, deploy to all environments via IaC or migration tooling
CREATE TABLE job_postings_fact (
    job_id INT NOT NULL PRIMARY KEY,
    job_title_short VARCHAR(100) NOT NULL,
    salary_year_avg DECIMAL(12, 2) NULL,  -- Nullable, handles missing data
    job_work_from_home BOOLEAN NOT NULL DEFAULT FALSE,
    job_posted_date DATE NOT NULL,
    job_location VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
)
PARTITION BY YEAR(job_posted_date);

-- In your pipeline code, validate against this schema before insert/upsert
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT
    job_id,
    job_title_short,
    NULLIF(salary_year_avg, 0) AS salary_year_avg,  -- Preserve nulls, don't coerce
    job_work_from_home,
    job_posted_date,
    job_location
FROM raw_job_postings
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 1 DAY;
```

## Notes

- **Common mistake:** Storing schema in documentation or letting DBAs manage prod separately. Define it as code (Terraform, dbt schema.yml, or migration scripts) and version-control it.
- **Env-specific config:** Parity doesn't mean identical *data*. Dev can have 100 rows, prod 100M. It means identical *structure, constraints, and logic*—use environment variables for resource counts and retention periods, not schema changes.
- **Connects to:** Infrastructure-as-code, schema versioning, and data contracts. A failing pipeline should reference the exact schema mismatch in its error message.
- **Testing gap:** Unit tests on sampled data miss schema issues. Use schema validation tests that run in all environments: `SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'job_postings_fact' AND is_nullable != 'NO'` should match your expected nullability.
- **Revisit:** How you handle schema evolution—adding a column in prod without updating dev creates new parity debt. Use backward-compatible migrations (add nullable first, backfill, then enforce constraints).
