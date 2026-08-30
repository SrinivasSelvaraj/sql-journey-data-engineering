---
date: 2026-08-30
phase: modelling
topic: Semantic layer: metric definitions and business logic reuse
---

# Semantic layer: metric definitions and business logic reuse

*Data modelling and warehousing*

## Concept

A semantic layer is a centralized definition of business logic that sits between raw data and end users. Instead of each analyst recalculating "active job postings" or "remote-work percentage" differently, the semantic layer defines these once—as metrics, dimensions, or derived tables—and everyone queries the same truth.

Without it, teams waste time rebuilding the same calculations, introduce inconsistencies (one person uses `job_posted_date > NOW() - INTERVAL 30 DAY`, another uses 60), and create bottlenecks when someone asks "what does 'active' mean?" The semantic layer answers that question upfront, embedded in code, not in Slack threads.

This is especially critical as a warehouse grows: it's the difference between scaling analysts (everyone self-serves with confidence) and scaling you (answering the same question repeatedly). Modern tools like dbt, Looker, or Cube make this practical by letting you define metrics as SQL once and reuse them everywhere.

## Practice

**Problem:** Your team needs to report on "high-value remote jobs posted recently." Three analysts define this differently: one filters for salary > 100k and `job_work_from_home = TRUE`, another adds a posted-within-30-days constraint but uses 90k as the threshold, and a third includes part-time roles. Reports don't match; stakeholders are confused.

**Solution:** Define the metric in a semantic layer (here shown as a dbt model serving as the single source of truth):

```sql
-- models/marts/job_postings_metrics.sql
select
  job_id,
  job_title_short,
  job_location,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  
  -- Metric: days since posted (reusable dimension)
  date_diff(day, job_posted_date, current_date()) as days_since_posted,
  
  -- Metric: is_recent (business logic: posted in last 30 days)
  case when date_diff(day, job_posted_date, current_date()) <= 30 then true else false end as is_recent,
  
  -- Metric: is_high_value (business logic: salary >= 100k)
  case when salary_year_avg >= 100000 then true else false end as is_high_value,
  
  -- Metric: is_high_value_remote_recent (compound business logic)
  case 
    when job_work_from_home = true 
      and salary_year_avg >= 100000 
      and date_diff(day, job_posted_date, current_date()) <= 30 
    then true 
    else false 
  end as is_high_value_remote_recent

from {{ ref('job_postings_fact') }}
```

Now every analyst queries the same metric:
```sql
select job_title_short, count(*) as count
from job_postings_metrics
where is_high_value_remote_recent = true
group by job_title_short;
```

## Notes

- **Avoid recalculation tax:** Don't leave business logic scattered in individual queries; centralize it once, use it everywhere. This prevents drift and saves cognitive load.
- **Documentation lives in code:** Use column descriptions in dbt `schema.yml` or tool-native docs so users see *why* a metric exists (e.g., "30 days chosen because our job boards refresh on that cadence").
- **Layer wisely:** Distinguish between staging (light cleaning), intermediate (reusable transformations), and marts (business-ready, documented metrics). Semantic definitions belong in marts.
- **Connect to governance:** The semantic layer is where you enforce data contracts—define what "remote" means once, version it, and alert if upstream data changes the definition.
- **Revisit: slowly-changing dimensions** (SCD) and **metric aggregation patterns** (sum, count, ratio); these often need semantic governance too.
