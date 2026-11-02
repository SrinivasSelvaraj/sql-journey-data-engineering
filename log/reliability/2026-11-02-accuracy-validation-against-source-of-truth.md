---
date: 2026-11-02
phase: reliability
topic: Accuracy: validation against source of truth
---

# Accuracy: validation against source of truth

*Quality, reliability and the professional layer*

## Concept

Accuracy validation means systematically comparing your pipeline outputs against a known source of truth—the canonical reference data that stakeholders trust. This isn't about checking for nulls or duplicates; it's about confirming that the *values themselves* match reality. A salary field might be populated and unique but wrong by $20k. A job location might be correctly formatted but point to the wrong city because of a faulty join. Without this validation, you ship incorrect data confidently, and by the time anyone notices, it's embedded downstream in dashboards, models, and decisions.

Validation becomes critical when: (1) stakeholders make decisions on your data, (2) the pipeline transforms or aggregates raw source data, or (3) you control a shared table that other teams depend on. The difference between a junior engineer and someone trusted to own a pipeline is this: juniors assume upstream data is correct and their transformations preserve it; owners actively prove both assumptions wrong on a schedule.

The cost of skipping this is hidden. Bad data doesn't always crash—it degrades quietly. A 5% error rate in salary data won't trigger an alert, but it will corrupt compensation analysis, hiring decisions, and model training. Validation catches systematic drift (a schema change upstream, a new data source, a changing business rule) before it propagates.

## Practice

**Problem:** Your `job_postings_fact` table aggregates data from three job boards. The source systems track `job_posted_date` and `salary_year_avg` as canonical truth. You need to detect any rows where these values have drifted from source after your transformations run.

```sql
-- Validation query: compare fact table against source of truth
with source_of_truth as (
  select
    job_id,
    job_posted_date as sot_posted_date,
    salary_year_avg as sot_salary
  from raw.job_boards_api  -- your system of record
  where job_posted_date >= current_date - interval '7 days'
),
fact_to_validate as (
  select
    job_id,
    job_posted_date,
    salary_year_avg
  from analytics.job_postings_fact
  where job_posted_date >= current_date - interval '7 days'
)
select
  f.job_id,
  f.job_posted_date as fact_date,
  s.sot_posted_date,
  f.salary_year_avg as fact_salary,
  s.sot_salary,
  case when f.job_posted_date != s.sot_posted_date then 'DATE_MISMATCH' end as date_issue,
  case when f.salary_year_avg != s.sot_salary then 'SALARY_MISMATCH' end as salary_issue
from fact_to_validate f
full outer join source_of_truth s on f.job_id = s.job_id
where f.job_posted_date != s.sot_posted_date
   or f.salary_year_avg != s.sot_salary
   or f.job_id is null
   or s.job_id is null;
```

Run this daily and alert if the row count exceeds zero. Log the results to a validation results table for audit.

## Notes

- **Confuse accuracy with completeness:** A table can be 100% complete (no nulls) and 0% accurate (all values wrong). These are separate quality dimensions requiring separate checks.
- **Don't validate against a derived source:** If your "source of truth" is itself a downstream transformation, you're checking your logic against itself. Identify the canonical system—usually the operational database or API that business users trust.
- **Sampling trap:** Spot-checking a few rows manually scales terribly. Automate and schedule the validation so it runs after every load; make mismatches visible in a dashboard.
- **Adjacent skills:** This connects to schema contracts (agreeing on what data means before building), data lineage tracking (knowing where each field came from), and incident response (what to do when validation fails—rollback? investigate? notify?).
- **Revisit when schemas change:** Any time a source adds a field, changes a calculation, or modifies a timestamp, add a validation rule for it immediately—don't wait for complaints.
