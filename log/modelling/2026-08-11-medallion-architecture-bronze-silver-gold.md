---
date: 2026-08-11
phase: modelling
topic: Medallion architecture: bronze, silver, gold
---

# Medallion architecture: bronze, silver, gold

*Data modelling and warehousing*

## Concept

The medallion architecture organizes data into three layers—bronze, silver, and gold—each serving a distinct purpose in the pipeline. Bronze holds raw, unprocessed ingests (API responses, logs, CSVs) exactly as received; silver contains cleaned, deduplicated, and lightly transformed data with consistent types and naming; gold layers materialized business entities (facts, dimensions) optimized for analytics and self-service queries. This matters because it forces clarity: analysts querying gold need zero context about how salary_year_avg was calculated or whether job_location is standardized; engineers in silver know exactly which transformations occurred and can audit data quality; bronze preserves lineage and enables recovery if transformation logic breaks. Without this separation, teams end up either asking "what does this column really mean?" constantly, or building fragile dependencies across dozens of undocumented staging tables.

## Practice

**Problem:** Your analytics team queries `job_postings_fact` and finds salary_year_avg values ranging from 25000 to 999999, with 15% NULLs. They don't know: are NULLs missing data or "no salary disclosed"? Are outliers real or sensor errors? Is the column USD or local currency? These questions reveal the fact table wasn't built with medallion discipline—no silver layer enforced rules.

**Solution:**

```sql
-- Silver: cleaned, validated, documented
CREATE TABLE job_postings_silver AS
SELECT
  job_id,
  job_title_short,
  CASE 
    WHEN salary_year_avg IS NULL THEN -1  -- explicit marker for "not disclosed"
    WHEN salary_year_avg < 20000 OR salary_year_avg > 500000 THEN NULL  -- outlier flag
    ELSE salary_year_avg
  END AS salary_year_avg_usd,
  job_work_from_home,
  job_posted_date,
  LOWER(TRIM(job_location)) AS job_location_normalized,
  salary_year_avg_original,  -- preserve raw for audit
  dbt_run_timestamp
FROM job_postings_bronze
WHERE job_posted_date >= '2023-01-01';

-- Gold: business-ready fact, with lineage and domain logic
CREATE TABLE job_postings_fact AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg_usd,  -- already validated in silver
  job_work_from_home,
  job_posted_date,
  job_location_normalized AS job_location,
  CASE WHEN salary_year_avg_usd = -1 THEN 'Not Disclosed'
       WHEN salary_year_avg_usd IS NULL THEN 'Outlier'
       ELSE 'Valid'
  END AS salary_validity
FROM job_postings_silver;
```

Now analysts query gold and trust the data; if they need to audit a salary value, they trace to silver (transformation rules) and bronze (original ingestion).

## Notes

- **Common mistake:** Skipping silver and jumping straight from bronze to gold. This embeds cleaning logic in BI tools or forces every analyst to re-validate; it breaks reproducibility.
- **Column naming debt:** Use suffixes in silver (`_normalized`, `_usd`, `_original`) so gold table names stay clean but lineage is obvious. Gold should feel like the "real" business table.
- **Connects to:** dbt staging vs. mart layers (staging ≈ silver, marts ≈ gold), SCD Type 2 dimension handling, and data contracts—gold tables should be documented with column lineage and business rules.
- **Revisit:** Decide early whether to hard-delete outliers (bronze→silver) or soft-delete with validity flags (easier to recover, auditable). Revisit when business rules change.
- **Testing & monitoring:** Add data quality checks (dbt tests) at the silver layer—null counts, domain ranges, freshness—so gold stays trustworthy without redundant checks.
