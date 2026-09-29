---
date: 2026-09-29
phase: reliability
topic: Outlier detection: statistical and domain-driven rules
---

# Outlier detection: statistical and domain-driven rules

*Quality, reliability and the professional layer*

## Concept

Outlier detection is the discipline of identifying anomalous records that deviate from expected patterns—either statistically (z-score > 3, IQR violations) or through business logic (a job posting with negative salary, a remote role in a location that doesn't exist). Without it, poisoned data flows downstream into analytics, ML models, and dashboards, where it silently corrupts insights and decisions.

The difference between "building pipelines" and "owning them" is knowing which outliers to reject, which to flag for review, and which signal a real change in the source system. A junior engineer removes all outliers; a senior one asks: *Is this bad data or a legitimate business event?* A $500k/year role might be an error—or it might be a C-suite executive search you didn't know existed.

Practical ownership means defining clear rules *before* data reaches consumers. Statistical thresholds work for continuous variables (salary, duration). Domain rules catch categorical impossibilities (job_location = null but job_work_from_home = false) and business logic violations (salary_year_avg < min_wage). Both belong in your pipeline, logged separately, so stakeholders can audit what was rejected and why.

## Practice

**Problem:** Your job postings pipeline receives data from multiple job boards. Some postings have salaries of $0 or $999,999. Remote roles sometimes have non-US locations; contract roles occasionally lack salary data. You need to catch genuine data quality issues without removing legitimate high-value or sparse records.

```sql
with outlier_flags as (
  select
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    -- Statistical: salary bounds (IQR-based)
    case
      when salary_year_avg = 0 then 'salary_zero'
      when salary_year_avg > 500000 then 'salary_extreme_high'
      when salary_year_avg < 25000 and job_work_from_home = false then 'salary_low_on_site'
      else null
    end as statistical_flag,
    -- Domain rules
    case
      when job_work_from_home = true and job_location like '%International%' then 'remote_location_mismatch'
      when job_work_from_home = false and job_location is null then 'on_site_no_location'
      when job_location not in (select distinct location from valid_locations_dim) then 'unknown_location'
      else null
    end as domain_flag
  from job_postings_raw
  where job_posted_date >= current_date - interval '7 days'
)
select
  job_id,
  job_title_short,
  salary_year_avg,
  job_location,
  statistical_flag,
  domain_flag,
  case
    when statistical_flag is not null or domain_flag is not null then 'flagged'
    else 'clean'
  end as quality_status,
  current_timestamp as checked_at
from outlier_flags
-- Log all flags, but only reject domain mismatches
where statistical_flag is not null or domain_flag is not null
order by job_id;
```

Insert flagged records into a `job_postings_quarantine` table; review before deciding rejection vs. acceptance.

## Notes

- **Conflating rejection with detection.** Flag outliers separately from filtering. You need audit trails showing what was rejected and why—your data governance partner will ask.
- **Ignoring temporal context.** What's an outlier today might be normal tomorrow. Salary spikes around year-end hiring; remote roles expand in downturns. Recalibrate thresholds quarterly.
- **Statistical rules without domain knowledge.** A z-score catches outliers but not impossibilities. Pair percentile analysis with business rules (e.g., "no job can post with salary = 0") for defense in depth.
- **Connects to:** data contracts (define acceptable ranges upstream), monitoring (alert when flag rates spike), and root-cause analysis (why did we get 200 zero-salary posts last Tuesday?).
- **Revisit:** How to handle sparse data (contract roles with optional salary). Consider separate pipelines for high-variance job types rather than one-size-fits-all thresholds.
