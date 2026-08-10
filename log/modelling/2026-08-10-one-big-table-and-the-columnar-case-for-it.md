---
date: 2026-08-10
phase: modelling
topic: One Big Table and the columnar case for it
---

# One Big Table and the columnar case for it

*Data modelling and warehousing*

## Concept

A One Big Table (OBT) is a denormalized, wide fact table that combines metrics, dimensions, and attributes into a single queryable surface. Instead of maintaining separate dimension tables (jobs, companies, locations) and joining them at query time, an OBT pre-joins everything into one wide row, with every context needed to understand a metric already present.

This matters most when your team queries the data directly without a semantic layer (like dbt metrics or a BI tool). When analysts write their own SQL, they need complete context—job title, location, salary, posting date—in one place. Without it, they either write increasingly complex joins (error-prone, slow to debug) or ask you repeatedly what columns mean and how they relate. The OBT trades storage for usability and query safety.

What breaks without it: analysts duplicate join logic across queries, leading to inconsistent salary calculations or filtered datasets. Onboarding new team members means teaching them your star schema. Simple questions like "average salary by location" become three-table joins. The OBT doesn't eliminate the need for dimensional thinking—it just surfaces it upfront in the warehouse layer, not in every analysis.

## Practice

**Problem:** An analyst needs to find the average salary for remote-friendly data analyst roles posted in the last 90 days, grouped by location. Without an OBT, they need to join job_postings to companies to locations. With the OBT below, they should write one simple query without guessing join keys.

```sql
SELECT 
  job_location,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_title_short LIKE '%Data Analyst%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY job_location
ORDER BY avg_salary DESC;
```

## Notes

- **Columnar storage is essential:** OBTs are wide (many columns). Parquet, Iceberg, or columnar databases let you scan only the columns you need (job_location, salary_year_avg) without reading job_title_short. Row-oriented storage makes OBTs painfully slow.

- **Naming discipline is non-negotiable:** Every column must be self-documenting. `salary_year_avg` is better than `salary`. Prefix by domain: `job_`, `company_`, `market_` so analysts see structure in autocomplete and know what they're selecting.

- **OBT is not a replacement for dimensional modeling—it's the final product of it.** You still design conformed dimensions and facts first; the OBT is built *from* those, not instead of them. Use dbt to materialize it as a view or table.

- **Beware slow-changing dimensions (SCD Type 2):** If job titles or locations change, decide: do you snapshot them at posting time (cleaner for OBT) or look them up live? OBT assumes you've already chosen and denormalized accordingly.

- **Revisit grain and cardinality:** An OBT at job_id grain can explode if you left-join in many-to-many relationships (e.g., skills). Validate that each row is truly one job posting, not one job-skill pair masquerading as an OBT.
