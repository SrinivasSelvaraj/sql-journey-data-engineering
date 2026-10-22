---
date: 2026-10-22
phase: reliability
topic: Data quality frameworks: Great Expectations and Soda
---

# Data quality frameworks: Great Expectations and Soda

*Quality, reliability and the professional layer*

## Concept

Data quality frameworks like Great Expectations and Soda shift ownership from "my pipeline runs" to "my data is trustworthy." They're declarative systems where you define expectations (schema validation, value ranges, freshness, uniqueness) once, then execute them continuously against live data. When data violates these rules, they halt pipelines or alert—preventing bad data from propagating downstream to analytics, ML models, or business decisions.

Without explicit quality gates, silent failures become your default. A salary column that unexpectedly contains nulls might produce wrong revenue forecasts for weeks. A date field that accepts future dates might corrupt reporting logic. Teams that own pipelines professionally—not just maintain them—instrument these checks early and treat failures as data problems to investigate, not pipeline exceptions to suppress.

Great Expectations is Python-first and checkpoint-heavy; Soda is lightweight YAML-driven and cloud-friendly. Both integrate into dbt workflows, data catalogs, and orchestrators. Choosing between them depends on your stack's maturity and whether you need programmatic control (GE) or operational simplicity (Soda).

## Practice

**Problem:** Your `job_postings_fact` table is fed by an unstable scraper. Recently: salary_year_avg spiked to $999,999,999 (data entry errors), job_posted_date included future dates, and job_title_short went null for 40% of rows. You need to catch these *before* they hit your analytics warehouse.

```sql
-- Define expectations as data quality rules
-- Example: Soda checks (YAML-style pseudo-code converted to checks)

SELECT 
  COUNT(*) as total_rows,
  COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_salaries,
  COUNT(CASE WHEN salary_year_avg > 500000 THEN 1 END) as outlier_salaries,
  COUNT(CASE WHEN job_posted_date > CURRENT_DATE THEN 1 END) as future_dates,
  COUNT(CASE WHEN job_title_short IS NULL OR job_title_short = '' THEN 1 END) as missing_titles,
  COUNT(DISTINCT job_id) as distinct_ids,
  COUNT(*) - COUNT(DISTINCT job_id) as duplicate_ids
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY;

-- Expected results for a healthy load:
-- null_salaries: < 5% of total_rows
-- outlier_salaries: < 1% of total_rows  
-- future_dates: = 0
-- missing_titles: < 2% of total_rows
-- duplicate_ids: = 0
```

In Great Expectations or Soda, you'd configure these as assertions that run post-load and block downstream dependencies if violated.

## Notes

- **Expectation creep:** Start with high-impact checks (nulls, duplication, key freshness) before adding statistical bounds. Over-specifying early creates maintenance debt and false positives.

- **Staging vs. live:** Run quality checks on *staging* tables before promotion to fact/dimension layers. This is where you decide to fail loudly or quarantine bad batches.

- **Connects to:** dbt `tests` (row-level logic) vs. these frameworks (volume/distribution-level) — they're complementary, not redundant. Also links to data observability, SLA monitoring, and incident response workflows.

- **Common mistake:** Treating quality rules as static. Data distributions shift; rules written for Q1 salary ranges need quarterly review. Build feedback loops between analysts and data engineers.

- **Revisit:** The difference between *validation* (schema/type) and *quality* (business logic). A null can be valid; it's a quality failure only if your downstream consumer can't handle it.
