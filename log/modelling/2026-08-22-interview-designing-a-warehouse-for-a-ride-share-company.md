---
date: 2026-08-22
phase: modelling
topic: Interview: designing a warehouse for a ride-share company
---

# Interview: designing a warehouse for a ride-share company

*Data modelling and warehousing*

## Concept

A well-designed warehouse schema for ride-share requires fact and dimension tables that encode business rules and metrics at the point of ingestion, not at query time. For ride-share, this means your facts (rides, payments, driver earnings) should have clear, immutable grain (one row per ride), and dimensions (driver, passenger, vehicle) should be conformed so that anyone querying knows whether "driver_id" includes inactive drivers, what "cancellation_reason" means, and which date column answers "when did this ride happen."

The cost of ambiguity is high: analysts write conflicting queries, stakeholders get different answers to the same question, and your team spends cycles in Slack arguing whether a cancelled ride counts as revenue. Without self-documenting schemas, every column becomes a tribal knowledge dependency on you.

Good schema design means column names are unambiguous (not `date` but `ride_completed_date`), nullable columns are rare and justified, and facts reference dimension primary keys (not driver names as strings). This shifts the burden from "ask the expert" to "follow the model."

## Practice

**Problem:** A stakeholder asks, "How many high-paying remote jobs were posted in the last 30 days?" Using the schema above, write a query that cannot be misinterpreted.

```sql
SELECT 
  COUNT(DISTINCT job_id) AS high_paying_remote_jobs_count,
  MIN(job_posted_date) AS earliest_post_date,
  MAX(job_posted_date) AS latest_post_date
FROM job_postings_fact
WHERE 
  job_work_from_home = TRUE
  AND salary_year_avg >= 120000
  AND job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY 1
ORDER BY 1 DESC;
```

The schema makes this unambiguous: `job_work_from_home` is a boolean (not a string "yes"/"no"), `salary_year_avg` is numeric (not a salary range), and `job_posted_date` is explicit (not confused with application date or job start date).

## Notes

- **Grain confusion kills schemas.** If a fact table mixes one row per ride with one row per ride + payment attempt, you'll double-count. Define grain explicitly in documentation.
- **Nullable columns are debt.** If `driver_phone` can be NULL, every query needs to decide if NULL means "not provided" or "opted out." Prefer a separate `driver_contact_preferences` dimension.
- **Dimension slowly-changing is adjacent.** Ride-share drivers change vehicle or status frequently. Track SCD Type 2 (version with effective dates) so historical queries stay correct.
- **Conformed dimensions matter across facts.** A `driver_dim` should be used by both `rides_fact` and `earnings_fact`, so "active drivers" has one definition.
- **Revisit cardinality assumptions.** If you assume one driver per ride, but surge pricing adds temporary contractors, your schema breaks. Build flexibility early.
