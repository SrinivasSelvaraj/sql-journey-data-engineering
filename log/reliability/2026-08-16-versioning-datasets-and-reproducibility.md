---
date: 2026-08-16
phase: reliability
topic: Versioning datasets and reproducibility
---

# Versioning datasets and reproducibility

*Quality, reliability and the professional layer*

## Concept

Dataset versioning is the practice of tracking schema changes, data distributions, and transformation logic over time—not just keeping one "current" copy. Without it, you face the reproducibility crisis: a stakeholder asks "why did the salary average drop 15% last month?" and you cannot rewind to the exact data state that produced last month's report. This matters most when multiple teams depend on your datasets, when regulatory audits require historical accuracy, or when you're debugging a stale model that trained on old data.

What breaks: analysts run the same query against today's fact table and get different numbers than yesterday because column definitions shifted, NULL handling changed, or upstream transformations were tweaked. You lose the ability to trace a metric back to its source. You cannot safely refactor transformations. You ship a model trained on v1 of your data, but production consumes v3—silent misalignment.

Versioning means maintaining a clear lineage: document schema migrations, tag dataset snapshots with dates or content hashes, and design tables to be append-only or to preserve historical snapshots. It is the difference between "we have data" and "we have trustworthy data."

## Practice

**Problem:** Your `job_postings_fact` table had `salary_year_avg` as an INTEGER. Six months ago, someone changed it to DECIMAL(10,2) to capture more precision. A dashboard was built on the old schema; it still runs but truncates fractional salaries. No one knows when the change happened or which historical records are affected.

**Solution:**

```sql
-- Create a versioned fact table with change tracking
CREATE TABLE job_postings_fact_v2 (
    job_id INT,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(255),
    
    -- Versioning columns
    dbt_valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dbt_valid_to TIMESTAMP,
    dbt_scd_id VARCHAR(32),  -- Type 2 SCD tracking
    is_current BOOLEAN DEFAULT TRUE
);

-- Log schema changes in a metadata table
CREATE TABLE dataset_versions (
    dataset_name VARCHAR(100),
    version_number INT,
    version_hash VARCHAR(64),
    schema_definition JSON,
    row_count INT,
    created_at TIMESTAMP,
    change_description TEXT
);

INSERT INTO dataset_versions VALUES (
    'job_postings_fact',
    2,
    MD5(CAST(ROW(job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location) AS STRING)),
    '{"salary_year_avg": "DECIMAL(10,2)"}',
    (SELECT COUNT(*) FROM job_postings_fact_v2),
    CURRENT_TIMESTAMP,
    'Changed salary_year_avg from INTEGER to DECIMAL(10,2) for precision'
);
```

## Notes

- **Schema drift is silent**: Use automated schema validation in your dbt tests or Great Expectations to catch unintended column changes before they propagate downstream.

- **Snapshot vs. append**: Decide upfront whether your fact table is a daily snapshot (rebuilds each day, naturally versioned) or an append-only log (must explicitly mark deletes/updates with valid_from/valid_to).

- **Connects to**: dbt's Slowly Changing Dimensions (SCD), data contracts, lineage tracking, and observability—all part of the trust layer.

- **Common mistake**: Treating versioning as "keeping backups." Versioning is intentional, documented, and queryable. A backup is just a copy.

- **Revisit**: How to version transformations (code version + data version together), how to communicate breaking changes to downstream teams, cost/performance trade-offs of maintaining historical snapshots.
