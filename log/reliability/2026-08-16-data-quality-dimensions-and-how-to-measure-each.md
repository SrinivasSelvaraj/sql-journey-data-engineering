---
date: 2026-08-16
phase: reliability
topic: Data quality dimensions and how to measure each
---

# Data quality dimensions and how to measure each

*Quality, reliability and the professional layer*

## Concept

Data quality dimensions define the measurable attributes that determine whether data is fit for purpose. The six primary dimensions are: **accuracy** (correct values), **completeness** (no missing values), **consistency** (uniform format and logic across systems), **timeliness** (available when needed), **uniqueness** (no unwanted duplicates), and **validity** (conforms to schema and rules). Without these, downstream analysts make decisions on false premises—a salary recorded in cents instead of dollars, a location field with mixed country formats, or job postings that arrive three weeks late all silently break trust before they break queries.

The difference between owning a pipeline and merely building one is the ability to measure degradation before it reaches users. A pipeline owner knows their data's baseline quality on each dimension and sets thresholds that trigger alerts. They document what "good enough" looks like for salary data (within 5% of manual sample) versus location data (100% non-null, standardized to ISO codes). This requires instrumenting pipelines with quality checks that run alongside transformations, not after the fact.

Quality dimensions interact: a dataset can be complete but inconsistent (all fields populated, but location formats vary wildly). Timeliness and completeness often trade off (arrive faster with 95% of records, or wait for 100%). Ownership means making these trade-offs explicit and revisiting them as business needs change.

## Practice

**Problem:** The `job_postings_fact` table is loaded daily from three sources (LinkedIn, Indeed, Glassdoor). You notice salary data in the reporting dashboard looks wrong—some jobs show $45,000 as "4500000" and others appear null. Location formats are inconsistent ("NYC", "New York, NY", "United States - New York"). Job postings sometimes arrive 2–3 days late. How do you measure and surface these issues?

```sql
-- Quality dimensions measurement and alerting
CREATE TABLE job_postings_quality_check AS
SELECT
  CURRENT_DATE as check_date,
  -- Completeness: % non-null salary
  ROUND(100.0 * SUM(CASE WHEN salary_year_avg IS NOT NULL THEN 1 ELSE 0 END) 
    / COUNT(*), 2) as salary_completeness_pct,
  
  -- Validity: salary in reasonable range (assume $20k–$500k is valid)
  ROUND(100.0 * SUM(CASE WHEN salary_year_avg BETWEEN 20000 AND 500000 THEN 1 ELSE 0 END) 
    / NULLIF(SUM(CASE WHEN salary_year_avg IS NOT NULL THEN 1 ELSE 0 END), 0), 2) as salary_validity_pct,
  
  -- Consistency: location follows standardized format (state abbreviation only)
  ROUND(100.0 * SUM(CASE WHEN job_location ~ '^[A-Z]{2}$' THEN 1 ELSE 0 END) 
    / COUNT(*), 2) as location_format_consistency_pct,
  
  -- Timeliness: % of records posted within last 2 days
  ROUND(100.0 * SUM(CASE WHEN job_posted_date >= CURRENT_DATE - 2 THEN 1 ELSE 0 END) 
    / COUNT(*), 2) as timeliness_within_2days_pct,
  
  -- Uniqueness: duplicate job_ids (should be 0)
  COUNT(*) - COUNT(DISTINCT job_id) as duplicate_job_ids,
  
  COUNT(*) as total_records
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 1
GROUP BY CURRENT_DATE;

-- Alert when dimensions breach thresholds
SELECT *
FROM job_postings_quality_check
WHERE salary_completeness_pct < 95
   OR salary_validity_pct < 98
   OR location_format_consistency_pct < 90
   OR timeliness_within_2days_pct < 85
   OR duplicate_job_ids > 0;
```

## Notes

- **Mistake: measuring without action.** Quality checks that don't trigger alerts or update SLAs become noise. Tie every metric to a defined threshold and an owner.
- **Mistake: treating all dimensions equally.** Timeliness might matter more than consistency for real-time dashboards; accuracy matters more than completeness for financial data. Baseline and weight by business impact.
- **Connection: data lineage and observability.** Quality dimensions are only useful if you can trace failures upstream—which source injected the bad salary? When? This is why lineage tooling (dbt, Databand, Monte Carlo) and transformation layer visibility matter.
- **Revisit: trade-offs scale with volume.** A small daily pipeline can afford 100% accuracy checks; a 10TB/day pipeline needs sampling strategies and statistical quality gates.
- **Adjacent: SLA contracts.** Quality dimensions become contractual. If you promise 99% timeliness to stakeholders, you own that metric and must explain bre
