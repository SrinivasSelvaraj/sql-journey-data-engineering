---
date: 2026-09-17
phase: modelling
topic: Grain conflict resolution across sources
---

# Grain conflict resolution across sources

*Data modelling and warehousing*

## Concept

A grain conflict occurs when the same logical fact table attempts to store metrics at different levels of detail. For example, if `job_postings_fact` mixes job-level attributes (one row per job posting) with company-level attributes (one company per many jobs), you create ambiguity: which row's salary represents the company? Which location is "the" company location?

Grain conflicts corrupt aggregations and force users to add confusing filters or joins just to get correct counts. They also make documentation impossible—you can't write a clear definition of what a row represents. The fix is enforcing a single, declared grain and splitting multi-grained data into separate fact tables or conformed dimensions.

Without grain discipline, queries that look simple (`SELECT AVG(salary_year_avg) GROUP BY company_id`) silently produce wrong answers because salary gets double-counted or nulled unpredictably. This is why grain is the first design decision in dimensional modeling—it's easier to build right than debug later.

## Practice

**Problem:** You have two data sources feeding `job_postings_fact`: one logs salary per job posting, another logs average company benefit spend (one row per company per month). You're asked to report average salary by company. How do you model this without corrupting the grain?

```sql
-- ❌ WRONG: Mixes job grain with company grain
-- salary_year_avg is per job, but company_benefit_spend is per company per month
SELECT 
  company_id,
  AVG(salary_year_avg) as avg_salary,
  SUM(company_benefit_spend) as total_benefits
FROM job_postings_fact
GROUP BY company_id;
-- Result: Benefits are summed multiple times (once per job posting)

-- ✅ RIGHT: Separate fact tables, each with declared grain
-- Grain: job_postings_fact = one row per job posting
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  company_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR
);

-- Grain: company_financials_fact = one row per company per month
CREATE TABLE company_financials_fact (
  company_id INT,
  fiscal_month DATE,
  company_benefit_spend DECIMAL,
  PRIMARY KEY (company_id, fiscal_month)
);

-- Now safe to join at correct grain:
SELECT 
  jp.company_id,
  AVG(jp.salary_year_avg) as avg_salary,
  AVG(cf.company_benefit_spend) as avg_monthly_benefits
FROM job_postings_fact jp
LEFT JOIN company_financials_fact cf 
  ON jp.company_id = cf.company_id
  AND TRUNC(jp.job_posted_date, 'MONTH') = cf.fiscal_month
GROUP BY jp.company_id;
```

## Notes

- **Confuse grain with cardinality:** grain is *which attributes define one row*, not how many rows exist. A job_postings_fact with 1M rows still has grain = one row per job posting.
- **Conformed dimensions reduce conflicts:** if company attributes (size, industry, region) live in a shared `dim_company` table instead of repeating in job_postings_fact, you eliminate redundancy and grain ambiguity.
- **Document grain in metadata:** your schema should include a comment on every fact table stating its grain explicitly. Users reading the DDL will know whether to GROUP BY job_id or company_id.
- **Degenerate dimensions and bridge tables:** when a single business entity needs multiple grains (e.g., job posting + hiring manager + company hiring plan), bridge tables or degenerate dimensions preserve grain while modeling relationships.
- **Revisit on source changes:** when a new upstream system arrives, re-audit all fact tables for grain conflicts before merging data—it's the cheapest fix point.
