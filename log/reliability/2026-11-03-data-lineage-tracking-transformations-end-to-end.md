---
date: 2026-11-03
phase: reliability
topic: Data lineage: tracking transformations end-to-end
---

# Data lineage: tracking transformations end-to-end

*Quality, reliability and the professional layer*

## Concept

Data lineage is the complete map of how data flows through your system—which tables feed which transformations, which business rules apply at each step, and where each column in a final output originated. Without it, you inherit "ghost data": columns you can't explain, calculations you can't defend, and failures you can't isolate.

This matters most when your pipeline owns critical decisions. When finance uses a salary metric from your job_postings table to set budgets, or recruiting uses your job_location standardization to staff regions, you need to prove every number is correct and reproducible. It's the difference between "we have data" and "we own this data."

Without lineage, debugging becomes detective work. A salary figure looks wrong—but which transformation introduced the error? Was it a null-handling rule in the bronze layer, a currency conversion in silver, or a rounding decision in gold? Did the source API change? Without tracing the path backward, you're guessing. You'll spend hours investigating what should take minutes.

## Practice

**Problem:** You maintain a fact table for job postings. The salary_year_avg column occasionally shows $0, and recruiting is questioning your data quality. You need to document and verify where every salary value comes from, what rules it passes through, and where it might drop to zero—so you can either fix the root cause or confidently explain it to stakeholders.

```sql
-- Step 1: Source lineage – trace salary from raw to fact
CREATE VIEW job_salary_lineage AS
SELECT
  jp.job_id,
  jp.job_title_short,
  -- Source layer: raw salary before any transformation
  jp_raw.salary_year_avg AS salary_raw,
  -- Validation: does it pass basic range checks?
  CASE 
    WHEN jp_raw.salary_year_avg IS NULL THEN 'null_in_source'
    WHEN jp_raw.salary_year_avg = 0 THEN 'zero_in_source'
    WHEN jp_raw.salary_year_avg < 15000 THEN 'below_minimum_wage'
    ELSE 'valid'
  END AS salary_validation_rule,
  -- Silver layer: standardized salary (after currency/unit normalization)
  jp_silver.salary_year_avg_usd AS salary_standardized,
  -- Gold layer: final fact table value
  jp.salary_year_avg AS salary_final,
  -- Transformation metadata
  jp_silver.currency_code,
  jp_silver.transformed_at,
  jp.job_posted_date,
  CURRENT_TIMESTAMP() AS lineage_traced_at
FROM job_postings_fact jp
LEFT JOIN job_postings_silver jp_silver ON jp.job_id = jp_silver.job_id
LEFT JOIN job_postings_raw jp_raw ON jp_silver.source_job_id = jp_raw.job_id
WHERE jp.salary_year_avg = 0 OR jp.salary_year_avg IS NULL;

-- Step 2: Document transformation logic
CREATE TABLE salary_transformation_rules (
  rule_id STRING,
  layer STRING,
  rule_name STRING,
  logic_description STRING,
  impact_count INT,
  last_updated TIMESTAMP
);

INSERT INTO salary_transformation_rules VALUES
  ('sal_001', 'bronze', 'null_passthrough', 'If source salary is NULL, remain NULL in bronze', 142, CURRENT_TIMESTAMP()),
  ('sal_002', 'silver', 'currency_normalization', 'Convert all salaries to USD using daily_rates table', 8, CURRENT_TIMESTAMP()),
  ('sal_003', 'silver', 'zero_replacement', 'If salary is 0 after normalization, mark as unknown and set to NULL', 34, CURRENT_TIMESTAMP()),
  ('sal_004', 'gold', 'coalesce_strategy', 'Use median salary by job_title_short if final salary is NULL', 76, CURRENT_TIMESTAMP());

-- Step 3: Audit trail – capture what happened to each record
SELECT
  job_id,
  salary_raw,
  salary_validation_rule,
  salary_standardized,
  currency_code,
  salary_final,
  CASE
    WHEN salary_raw IS NULL THEN 'Failed at: source is null'
    WHEN salary_raw = 0 THEN 'Failed at: source is zero'
    WHEN salary_standardized IS NULL THEN 'Failed at: standardization lost value'
    WHEN salary_final = 0 THEN 'Failed at: coalesce/fill strategy'
    ELSE 'Passed all validations'
  END AS data_quality_status
FROM job_salary_lineage
ORDER BY job_posted_date DESC;
```

## Notes

- **Lineage ≠ logging.** Logging tells you *what ran*; lineage tells you *what changed and why*. You need both, but lineage is about intent and business rules, not execution timestamps.
- **Version your transformations like code.** When you change a salary standardization rule
