---
date: 2026-08-16
phase: reliability
topic: Great Expectations or Soda for validation
---

# Great Expectations or Soda for validation

*Quality, reliability and the professional layer*

## Concept

Data validation tools like Great Expectations and Soda are the difference between a pipeline that *runs* and a pipeline you can *trust*. They catch data quality issues before they propagate downstream—malformed schemas, null where there shouldn't be, impossible values, drift in distributions—and either fail loudly or trigger alerts. Without them, bad data silently corrupts reports, models, and decisions. You end up debugging dashboards instead of preventing the problem.

Great Expectations (GE) uses Python-first test definitions and stores results as artifacts; Soda uses YAML configs and integrates tightly with data catalogs. Both sit between your ingestion layer and analytics/ML consumption. The real power isn't the tool—it's treating validation as infrastructure, not an afterthought. You own the pipeline's reliability when you can answer: "What assertions must be true for this data to be safe to use?"

This is the shift from "my pipeline works" to "my pipeline is production-grade." It's where you move from hope-driven development to contract-driven development.

## Practice

**Problem:** Your `job_postings_fact` ingests daily job listings. Recently, you noticed salary_year_avg contains impossible negatives, job_work_from_home has unexpected NULL values in rows that should be complete, and job_posted_date occasionally contains future dates. You need to catch these before they reach downstream dashboards.

```sql
-- Great Expectations / Soda validation queries
-- 1. Salary must be non-negative (if not NULL)
SELECT COUNT(*) as invalid_salary_count
FROM job_postings_fact
WHERE salary_year_avg < 0;

-- 2. job_work_from_home should never be NULL
SELECT COUNT(*) as missing_wfh_count
FROM job_postings_fact
WHERE job_work_from_home IS NULL;

-- 3. job_posted_date should not be in the future
SELECT COUNT(*) as future_date_count
FROM job_postings_fact
WHERE job_posted_date > CURRENT_DATE;

-- 4. Completeness: at least 95% of rows should have salary data
SELECT ROUND(100.0 * COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) / COUNT(*), 2) as salary_completeness_pct
FROM job_postings_fact;

-- 5. Freshness: most recent job_posted_date should be within last 24 hours
SELECT CASE 
  WHEN MAX(job_posted_date) >= CURRENT_DATE - INTERVAL 1 DAY THEN 'FRESH'
  ELSE 'STALE'
END as freshness_check
FROM job_postings_fact;
```

These checks become assertions in GE (`.expect_column_values_to_be_between()`) or Soda rules (`missing_count`, `freshness`), and they run automatically after ingestion.

## Notes

- **Common mistake:** Writing validation rules that are too loose (e.g., "salary < 999999999") and missing real problems. Your assertions should reflect business logic, not just technical boundaries.
- **Adjacent topic:** This connects directly to data contracts and schema validation (Pydantic, protobuf). Validation is useless if the schema itself is broken before it arrives.
- **Integration point:** Pair validation with alerting—a failing check that no one sees is theater. Wire results to Slack, PagerDuty, or your data platform's observability layer.
- **Revisit often:** Data quality rules drift. What was a good assertion in month 1 may be too strict (false positives) or too loose (missed issues) by month 6. Review assertions quarterly when patterns change.
- **Tool choice matters less than discipline:** GE vs. Soda is less important than *consistently defining and monitoring* what "good data" means. Pick one and commit.
