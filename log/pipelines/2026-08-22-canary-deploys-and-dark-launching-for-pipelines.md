---
date: 2026-08-22
phase: pipelines
topic: Canary deploys and dark launching for pipelines
---

# Canary deploys and dark launching for pipelines

*Pipelines and orchestration*

## Concept

Canary deploys and dark launching are risk-mitigation patterns for pipeline changes. A canary deploy routes a small percentage of traffic or data through the new pipeline logic while keeping the majority on the stable version; dark launching runs the new pipeline in parallel without affecting downstream consumers, comparing outputs for correctness before full cutover. Both let you catch bugs, performance regressions, and data quality issues in production before they break dashboards or dependent systems.

Without these patterns, a faulty transformation or schema change can corrupt months of historical data or cause silent failures that propagate downstream—sometimes undetected for days. A single miscalculated salary_year_avg or a forgotten null check can invalidate reports that executives depend on. Canary and dark launch strategies let you gain confidence in a change incrementally, using real production volume and edge cases that staging never captures.

The pattern is essential when you cannot easily rollback (immutable data warehouses), when pipelines feed mission-critical reports, or when you lack comprehensive monitoring. It trades deployment speed for safety and observability.

## Practice

**Problem:** You've refactored the salary_year_avg calculation to handle a new currency conversion rule, but you're unsure if the logic correctly handles edge cases (nulls, zero values, outliers). You need to deploy this safely to production without corrupting the fact table.

**Solution:** Deploy a canary by creating a staging column, running both old and new logic in parallel, and validating before promotion:

```sql
-- Step 1: Add a canary column to job_postings_fact
ALTER TABLE job_postings_fact
ADD COLUMN salary_year_avg_v2 DECIMAL(10, 2) DEFAULT NULL;

-- Step 2: Populate canary column with new logic (run only on small subset initially)
UPDATE job_postings_fact
SET salary_year_avg_v2 = 
  CASE 
    WHEN salary_year_avg IS NULL THEN NULL
    WHEN salary_year_avg = 0 THEN 0
    ELSE ROUND(salary_year_avg * 1.05, 2)  -- new conversion rule
  END
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
  AND job_id % 100 < 10;  -- canary: only 10% of recent jobs

-- Step 3: Validate canary results
SELECT 
  COUNT(*) as total_records,
  COUNT(CASE WHEN salary_year_avg IS NULL AND salary_year_avg_v2 IS NOT NULL THEN 1 END) as unexpected_changes,
  ROUND(AVG(salary_year_avg), 2) as old_avg,
  ROUND(AVG(salary_year_avg_v2), 2) as new_avg,
  MAX(salary_year_avg_v2 - salary_year_avg) as max_diff
FROM job_postings_fact
WHERE salary_year_avg_v2 IS NOT NULL;

-- Step 4: If validation passes, expand canary to 100%
UPDATE job_postings_fact
SET salary_year_avg_v2 = 
  CASE 
    WHEN salary_year_avg IS NULL THEN NULL
    WHEN salary_year_avg = 0 THEN 0
    ELSE ROUND(salary_year_avg * 1.05, 2)
  END
WHERE salary_year_avg_v2 IS NULL;

-- Step 5: After final validation, promote and drop old column
ALTER TABLE job_postings_fact
DROP COLUMN salary_year_avg;

ALTER TABLE job_postings_fact
RENAME COLUMN salary_year_avg_v2 TO salary_year_avg;
```

## Notes

- **Common mistake:** Deploying canaries only to fresh data; always include a sample of historical data to catch bugs that only surface under real-world volume and age distributions.
- **Shadow validation:** Run the new pipeline write to a shadow table (not the source of truth) and compare row counts, checksums, and sample outputs before cutover; automate this comparison as part of your DAG.
- **Monitoring the canary:** Set alerts on divergence metrics (count mismatch, null rate spike, outlier thresholds) so you catch failures fast; a silent canary that nobody checks defeats the purpose.
- **Connects to:** Feature flags (same principle applied to code), gradual rollouts, and feature stores; also relates to idempotency and replayability—ensure your pipeline can re-run the canary window without duplication.
- **Revisit:** Rollback procedures and data lineage tracking; know exactly which downstream tables depend on a column before you change it.
