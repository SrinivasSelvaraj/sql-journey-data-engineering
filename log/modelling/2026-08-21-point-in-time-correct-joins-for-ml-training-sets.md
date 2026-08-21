---
date: 2026-08-21
phase: modelling
topic: Point-in-time correct joins for ML training sets
---

# Point-in-time correct joins for ML training sets

*Data modelling and warehousing*

## Concept

Point-in-time (PIT) correct joins ensure that when you train an ML model on historical data, each training example uses only the information that was *actually available* at prediction time. Without this, you leak future data into your features—your model learns patterns that won't exist when you deploy it.

The core issue: dimension tables change. A customer's credit score updates, a product's category gets reclassified, an employee moves departments. If you join a fact table to the latest version of a dimension, you're retroactively applying those changes to old records. Your model trains on a version of reality that never existed.

This matters most when building training sets from transactional data (events, purchases, applications) joined against slowly-changing dimensions. The cost of ignoring it is high: models that perform well in backtests but fail in production because they saw tomorrow's data yesterday.

## Practice

**Problem:** You're building a churn prediction model. You have a `job_postings_fact` table with application dates. You need to join each posting to the job's location and remote status *as it was on the posting date*, not as it is today. The company has changed locations and remote policies multiple times. How do you prevent joining to future versions of the job?

```sql
-- Assume a slowly-changing dimension:
-- job_dim(job_id, job_location, job_work_from_home, valid_from DATE, valid_to DATE, is_current BOOLEAN)

SELECT 
  f.job_id,
  f.job_title_short,
  f.salary_year_avg,
  d.job_location,
  d.job_work_from_home,
  f.job_posted_date
FROM job_postings_fact f
INNER JOIN job_dim d 
  ON f.job_id = d.job_id
  AND f.job_posted_date >= d.valid_from
  AND f.job_posted_date < d.valid_to
ORDER BY f.job_posted_date;
```

The join condition `f.job_posted_date >= d.valid_from AND f.job_posted_date < d.valid_to` ensures each posting matches the dimension record that was active on its posting date.

## Notes

- **SCD Type 2 is your friend:** Slowly Changing Dimension Type 2 (versioning with `valid_from`/`valid_to` dates) is the standard pattern; resist the urge to just overwrite old values.
- **Test with backtesting windows:** Always validate that your training set uses only data available before your prediction date. A simple sanity check: the max date in your training set should be strictly before your backtest start date.
- **Watch for soft deletes:** If records are marked `is_deleted = true` rather than removed, you must filter them during the join; otherwise you'll train on "customers" that don't exist yet.
- **Connects to:** feature stores (Tecton, Feast) abstract away PIT logic; data vaults and dimensional modeling both rely on this concept; temporal databases offer native PIT queries.
- **Revisit:** The trade-off between storage (duplicating dimension history) and query complexity; how to handle dimensions that are updated *after* a fact was recorded but before you build your training set.
