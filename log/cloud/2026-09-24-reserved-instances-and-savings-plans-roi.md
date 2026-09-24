---
date: 2026-09-24
phase: cloud
topic: Reserved instances and savings plans ROI
---

# Reserved instances and savings plans ROI

*Cloud platforms and storage*

## Concept

Reserved instances (RIs) and savings plans commit you to a predictable compute footprint over 1–3 years in exchange for 30–70% discounts versus on-demand pricing. They matter because cloud bills often dwarf engineering costs; a data warehouse running 24/7 can cost $10k–50k monthly on-demand but $3k–15k with RIs. They break when your workload is unpredictable (spiky, ephemeral, or about to migrate), when you over-commit and waste reserved capacity, or when you forget to track utilization and let discounts expire unused. ROI calculation is straightforward: measure monthly on-demand cost, apply your region's RI discount rate, and divide the upfront commitment by monthly savings to get payback period (usually 3–6 months for stable workloads).

## Practice

**Problem:** Your analytics team runs daily aggregation jobs on a PostgreSQL database. You need to identify which job posting salary ranges should reserve compute capacity, so you can estimate on-demand vs. reserved costs over a year.

```sql
SELECT 
  CASE 
    WHEN salary_year_avg < 50000 THEN 'entry'
    WHEN salary_year_avg BETWEEN 50000 AND 100000 THEN 'mid'
    WHEN salary_year_avg > 100000 THEN 'senior'
  END AS salary_band,
  COUNT(*) AS job_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  ROUND(COUNT(*) * 0.12, 0) AS estimated_daily_compute_hours, -- assume 12 min per job
  ROUND(COUNT(*) * 0.12 * 365 * 0.20, 2) AS annual_on_demand_usd, -- $0.20/hour example
  ROUND(Count(*) * 0.12 * 365 * 0.06, 2) AS annual_reserved_1yr_usd   -- 70% discount
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY salary_band
ORDER BY avg_salary;
```

This query segments workload by salary tier and projects on-demand vs. reserved costs. Reserve capacity for the "senior" band if it's consistently high volume.

## Notes

- **Over-commitment trap:** Reserving 500 hours/month then migrating to Snowflake mid-contract leaves unused capacity; buy RIs only after 2–3 months of stable utilization data.
- **Blended pricing hides truth:** Always decompose bills into compute, storage, and data transfer; a "slow query" costing $50 might be cheap compute but expensive scan bytes.
- **Savings plans vs. RIs:** Savings plans are more flexible (work across instance families and regions) but require commitment discipline; RIs are cheaper if your hardware choice is locked in.
- **Ephemeral workloads stay on-demand:** CI/CD pipelines, dev environments, and one-off backfills should never touch reserved capacity.
- **Revisit quarterly:** Cloud pricing changes, new instance types launch, and business priorities shift—audit RI utilization and re-baseline ROI every 90 days.
