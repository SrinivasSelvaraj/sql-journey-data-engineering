---
date: 2026-08-17
phase: reliability
topic: Designing a system design interview answer
---

# Designing a system design interview answer

*Quality, reliability and the professional layer*

## Concept

The difference between "building a pipeline" and "owning a system" is accountability for what happens *after* deployment. Quality, reliability, and the professional layer means designing systems that gracefully degrade, surface problems early, and can be debugged by someone other than the author six months later. This includes SLAs (Service Level Agreements), monitoring, alerting, data contracts, and documentation that ties business impact to technical decisions.

Without this layer, you inherit technical debt: silent data corruption, cascading failures that take hours to diagnose, on-call rotations where nobody knows what went wrong, and stakeholders who stop trusting your pipelines. A pipeline owner doesn't just ask "does it work today?" but "what breaks it, how will we know, and who fixes it at 3am?"

Practically, this means: defining what "correct" looks like before building (data contracts), implementing checks that fail loudly rather than propagate bad data, structuring code for observability, and documenting the "why" of architectural choices—not just the code.

## Practice

**Problem:** You're tasked with building a daily dashboard of job market insights. The business needs to know: for each job title, the count of postings, average salary, and % remote work. The pipeline runs at 6am UTC daily. Your stakeholders check the dashboard at 8am. What quality and reliability considerations matter here?

```sql
-- Data contract: Define expectations upfront
-- 1. No NULL salaries for published postings (reject rows where salary_year_avg IS NULL)
-- 2. Salary range: $30k–$500k (data quality check)
-- 3. Posted date must be within last 90 days (freshness guarantee)
-- 4. Row count should not drop >20% day-over-day (volume anomaly)

-- Implementation with monitoring hooks:
CREATE TABLE job_market_daily AS
WITH validated AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    CURRENT_DATE() as load_date
  FROM job_postings_fact
  WHERE 
    job_posted_date >= CURRENT_DATE() - INTERVAL 90 DAY
    AND salary_year_avg BETWEEN 30000 AND 500000
    AND salary_year_avg IS NOT NULL
),
quality_checks AS (
  SELECT
    COUNT(*) as row_count,
    COUNT(DISTINCT job_title_short) as title_count,
    MIN(salary_year_avg) as min_salary,
    MAX(salary_year_avg) as max_salary
  FROM validated
)
SELECT
  job_title_short,
  COUNT(*) as posting_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary_year,
  ROUND(100.0 * SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_remote,
  CURRENT_DATE() as metric_date
FROM validated
GROUP BY job_title_short
ORDER BY posting_count DESC;

-- Monitoring query (run post-pipeline):
SELECT
  'row_count_check' as check_name,
  (SELECT COUNT(*) FROM job_market_daily WHERE metric_date = CURRENT_DATE()) as current_count,
  LAG(COUNT(*)) OVER (ORDER BY metric_date) as previous_count,
  ROUND(100.0 * ((SELECT COUNT(*) FROM job_market_daily WHERE metric_date = CURRENT_DATE()) - 
    LAG(COUNT(*)) OVER (ORDER BY metric_date)) / LAG(COUNT(*)) OVER (ORDER BY metric_date), 1) as pct_change
FROM job_market_daily
WHERE metric_date >= CURRENT_DATE() - 1;
```

## Notes

- **Mistake:** Validating data *inside* the transformation. Instead, validate early, fail loudly, and log rejected rows to a dead-letter table for investigation.
- **Mistake:** Assuming downstream consumers know your assumptions. Write a data dictionary: what each metric means, how it's calculated, known limitations (e.g., "salary data missing for 15% of postings").
- **Adjacent topics:** Observability (logging, metrics, traces), incident response (runbooks), schema evolution (how to change definitions without breaking dashboards), and cost optimization (reliability costs money).
- **Revisit:** The difference between testing pipelines (unit/integration tests) and monitoring pipelines (runtime SLI/SLO). You need both.
- **Key mindset:** Trust is built through transparency. If your pipeline fails, stakeholders should know *why* and *when* before they discover it via a wrong dashboard number.
