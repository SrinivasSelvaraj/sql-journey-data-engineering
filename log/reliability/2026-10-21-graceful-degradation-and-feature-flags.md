---
date: 2026-10-21
phase: reliability
topic: Graceful degradation and feature flags
---

# Graceful degradation and feature flags

*Quality, reliability and the professional layer*

## Concept

Graceful degradation is the ability for a data pipeline to continue producing value when part of it fails, rather than breaking completely. Feature flags are the mechanism: conditional logic that allows you to toggle pipeline behavior—skip expensive transformations, use cached data, reduce dimensions, or serve stale results—without redeploying code. 

This matters because production pipelines are not development environments. A third-party API goes down, a schema changes unexpectedly, a compute resource hits quota limits, or a new enrichment takes 3x longer than estimated. Without degradation patterns, your entire pipeline fails, your stakeholders lose access to data they depend on, and you're debugging at 2am. With them, you detect the failure, flip a flag, and keep the business moving while you fix the root cause.

The difference between someone who deploys pipelines and someone trusted to own them is often this: the owner asks "what breaks when X fails?" before it happens, and codes for it. They instrument feature flags into ETL logic, maintain a decision matrix for when to degrade, and document it so others can maintain it.

## Practice

**Problem:** Your `job_postings_fact` table depends on an external salary API that enriches `salary_year_avg`. The API is flaky and sometimes times out. When it fails, your entire daily load fails and analysts can't access job posting data at all.

**Solution:** Add a feature flag and fallback logic that uses yesterday's salary values when the API is unavailable.

```sql
-- Control flag (stored in a metadata table or environment variable)
-- SET @enable_live_salary_enrichment = false;  -- flip to true when API recovers

WITH api_response AS (
  SELECT 
    job_id,
    job_title_short,
    CASE 
      WHEN @enable_live_salary_enrichment = true 
        THEN call_salary_api(job_id)  -- your enrichment UDF
      ELSE null
    END AS api_salary
  FROM raw_job_postings
),
enriched AS (
  SELECT 
    job_id,
    job_title_short,
    COALESCE(
      api_response.api_salary,
      lag_salary.salary_year_avg,  -- fallback to yesterday's value
      0  -- final fallback to null/zero if no history
    ) AS salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM api_response
  LEFT JOIN job_postings_fact AS lag_salary
    ON api_response.job_id = lag_salary.job_id
)
SELECT * FROM enriched;
```

## Notes

- **Degradation is not the same as error handling.** A try-catch that logs and fails is error handling. Degradation means you detected the risk zone and chose a lower-quality-but-nonzero path forward.
- **Feature flags need visibility.** Log every time a flag triggers a degradation path. If you don't know it happened, you'll never prioritize fixing the root cause, and degradation becomes permanent.
- **Stale data is better than no data**—but document the staleness. Add a metadata column (`data_degraded_at`, `enrichment_skipped`) so downstream users and BI tools know what they're looking at.
- **Connect this to observability and SLOs.** Graceful degradation without alerting just hides problems. Pair it with monitors: "salary_api_unavailable for >30min triggers flag flip" and "degrade_flag_active for >4 hours escalates to page."
- **Revisit the decision matrix quarterly.** Which degradations are actually acceptable? Does stale salary data break your use case? Would sampling instead of full enrichment work? As the pipeline matures, your tolerance for degradation changes.
