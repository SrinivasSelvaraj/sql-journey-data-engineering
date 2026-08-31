---
date: 2026-08-31
phase: modelling
topic: Money and decimal precision: avoiding floating point
---

# Money and decimal precision: avoiding floating point

*Data modelling and warehousing*

## Concept

Floating-point arithmetic (IEEE 754) introduces rounding errors that compound silently in financial calculations. A value like `$99.99` stored as `FLOAT` or `DOUBLE` becomes `99.98999...` due to binary representation limits. When you sum 1,000 salaries or calculate bonuses, these micro-errors accumulate into data that fails audits and breaks downstream reporting.

In data warehouses, money belongs in `DECIMAL(precision, scale)` or `NUMERIC` types—fixed-point decimals that store exact base-10 values. `DECIMAL(10, 2)` means 10 total digits with exactly 2 after the decimal point: safe for USD, EUR, or any currency up to $99,999,999.99. This choice is not optional for finance, payroll, or billing; it's a schema contract that prevents silent data loss.

Dates and timestamps deserve the same discipline: use native `DATE` and `TIMESTAMP` types, never store them as strings or Unix epochs without explicit documentation. Precision failures here cascade into joins, period-over-period calculations, and regulatory compliance queries that teams query without ever asking you what the column *actually* means.

## Practice

**Problem:** The `job_postings_fact` table stores `salary_year_avg` as `FLOAT`. Finance wants to calculate total salary spend by location for budget forecasting. A query summing 50,000 salaries is off by $47 due to accumulated rounding—and you don't notice until the CFO's reconciliation fails.

```sql
-- ❌ WRONG: FLOAT loses precision
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg FLOAT,  -- BREAKS on large aggregations
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
);

-- ✅ CORRECT: DECIMAL for money
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10, 2),  -- Exactly $0.01 precision, no rounding errors
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
);

-- Safe to aggregate without surprises
SELECT 
  job_location,
  COUNT(*) as job_count,
  SUM(salary_year_avg) as total_spend,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
GROUP BY job_location;
```

## Notes

- **Type discipline is a contract:** Once `salary_year_avg` is `DECIMAL(10, 2)`, every downstream query inherits that guarantee. A colleague querying it 6 months later doesn't need to ask "is this exact money or an approximation?"
- **Scale matters more than precision:** `DECIMAL(18, 2)` handles USD up to $9,999,999,999.99. Know your domain's max value and lock it in the schema—ambiguity leads to "let's just use 10 digits" decisions that fail in production.
- **Joins and conversions are danger zones:** If one table has `DECIMAL(10, 2)` and another has `FLOAT`, implicit casting reintroduces rounding. Always cast explicitly in queries and document the direction.
- **Dates are money's silent partner:** Misaligned date precision (DATE vs. TIMESTAMP vs. string) causes period reconciliation failures. Use `DATE` for business events, `TIMESTAMP` for audit trails—never leave this ambiguous.
- **Revisit edge cases:** Negative values (refunds, adjustments), NULL vs. zero, currency conversion rates—all need schema-level clarity so queries don't require tribal knowledge.
