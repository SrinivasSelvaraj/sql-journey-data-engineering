---
date: 2026-09-01
phase: pipelines
topic: Feature flags for gradual pipeline rollout and testing
---

# Feature flags for gradual pipeline rollout and testing

*Pipelines and orchestration*

## Concept

Feature flags in data pipelines enable controlled rollout of transformations, schema changes, and new logic without halting production. Instead of deploying a pipeline version that affects all downstream consumers at once, flags let you run the old and new logic in parallel, validate results, and route traffic gradually. This is critical when a transformation logic change could corrupt metrics, break dependent dashboards, or introduce latency spikes.

Without feature flags, you face a binary choice: deploy and risk breaking everything, or delay deployment until you're certain (which rarely happens). With flags, you catch logic bugs, performance regressions, and data quality issues on a subset of jobs before full rollout. They also enable safe rollback—if the new logic fails, you flip a flag rather than revert code and re-run the entire pipeline.

Feature flags pair well with comprehensive pipeline monitoring: you need to compare old-path vs. new-path metrics side-by-side, check row counts, validate schema compliance, and alert on divergence. Without visibility into both branches, the flag is just a kill switch.

## Practice

**Problem:** You're refactoring the salary calculation in `job_postings_fact` to handle currency conversion for international postings. The old logic ignores currency; the new logic converts to USD. You need to run both calculations, compare results on 10% of jobs, and only switch 100% when confident.

```sql
-- Add a feature flag column and dual calculation logic
ALTER TABLE job_postings_fact 
ADD COLUMN salary_year_avg_new NUMERIC,
ADD COLUMN feature_flag_currency_conversion BOOLEAN DEFAULT FALSE;

-- Populate: old logic for everyone, new logic when flag is TRUE
UPDATE job_postings_fact
SET salary_year_avg_new = CASE 
  WHEN feature_flag_currency_conversion THEN 
    salary_year_avg * exchange_rate_for_date(job_posted_date, job_currency)
  ELSE salary_year_avg
END;

-- Canary: enable for 10% sample (e.g., by job_id hash)
UPDATE job_postings_fact
SET feature_flag_currency_conversion = TRUE
WHERE MOD(job_id, 10) = 0;

-- Validation query: compare old vs. new
SELECT 
  COUNT(*) as total_jobs,
  COUNT(CASE WHEN feature_flag_currency_conversion THEN 1 END) as new_logic_jobs,
  AVG(salary_year_avg) as old_avg,
  AVG(salary_year_avg_new) as new_avg,
  STDDEV(salary_year_avg_new - salary_year_avg) as conversion_stddev
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

-- Once validated, migrate production view to new column and remove flag
CREATE OR REPLACE VIEW job_postings_fact AS
SELECT job_id, job_title_short, salary_year_avg_new as salary_year_avg, 
       job_work_from_home, job_posted_date, job_location
FROM job_postings_fact_staging;
```

## Notes

- **Shadow vs. canary vs. blue-green:** Shadow runs both paths invisibly (heaviest compute, safest); canary routes a percentage (balances risk and cost); blue-green swaps entire environments (coarse-grained, best for schema changes). Pick based on blast radius and data volume.

- **Flag debt accumulates:** Stale flags clutter code and multiply test paths. Set expiration dates and automation to remove flags after promotion. Document the rollout timeline upfront.

- **Connects to:** data quality monitoring (you *must* compare metrics), testing strategies (integration tests should validate both flag states), and incident playbooks (flag flip should be the fastest rollback mechanism).

- **Common mistake:** Leaving both paths in production forever "just in case." This doubles query cost and creates hidden technical debt. Commit to a flag lifecycle: enable → canary → rollout → removal (timeline: 1–4 weeks).

- **Worth revisiting:** Feature flags interact with schema versioning (backward compatibility), idempotency (if you re-run with flags, do old and new logic both execute?), and cost tracking (how much does running both paths cost per day?).
