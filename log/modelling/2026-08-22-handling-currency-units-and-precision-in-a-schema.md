---
date: 2026-08-22
phase: modelling
topic: Handling currency, units and precision in a schema
---

# Handling currency, units and precision in a schema

*Data modelling and warehousing*

## Concept

Currency, units, and precision are metadata that must live *in your schema*, not in documentation or tribal knowledge. Without explicit handling, a column named `salary_year_avg` is ambiguous: is it USD or GBP? Gross or net? Rounded to the nearest dollar or cent? When analysts query the warehouse independently, they will make wrong assumptions—especially across borders or when joining datasets from different systems. Precision matters too: storing `3.14159` when you only need `3.14` wastes storage and confuses downstream consumers about what level of accuracy the data actually supports.

The cost of unclear units is high. A `distance` column might be miles, kilometers, or meters. A `temperature` could be Celsius or Fahrenheit. A `price` might be per unit, per thousand units, or per shipment. These mistakes compound when data is joined, aggregated, or used in machine learning pipelines. Establishing a convention—and enforcing it in column names, data types, and documentation—makes your schema self-documenting and prevents silent errors.

## Practice

**Problem:** The `job_postings_fact` table has a `salary_year_avg` column. A junior analyst sees it, assumes it's in USD, and builds a report comparing salaries across UK and US jobs. The UK salaries are stored in GBP. The analysis is published with no currency conversion, inflating UK salary figures by ~25%.

**Solution:**

```sql
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10, 2),
    salary_year_avg_currency_code CHAR(3),  -- ISO 4217: USD, GBP, EUR, etc.
    salary_year_avg_precision VARCHAR(50),  -- e.g., "rounded to nearest dollar"
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100)
);

-- Explicit naming for international context
ALTER TABLE job_postings_fact 
RENAME COLUMN salary_year_avg TO salary_year_avg_usd_dollars;

-- Or: store as a single canonical currency with conversion timestamp
CREATE TABLE job_postings_fact_v2 (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg_usd DECIMAL(10, 2),  -- normalized to USD
    salary_year_avg_original_value DECIMAL(10, 2),
    salary_year_avg_original_currency CHAR(3),
    salary_conversion_rate DECIMAL(10, 6),
    salary_conversion_date DATE,  -- when rate was current
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100)
);
```

## Notes

- **Naming is half the battle:** `salary_usd`, `distance_km`, `temperature_celsius` remove ambiguity instantly. Avoid generic names like `value` or `amount`.
- **Precision in the column type matters:** Use `DECIMAL(10, 2)` for money (fixed scale), not `FLOAT` (which loses precision). Document whether values are rounded, truncated, or averaged.
- **Currency codes belong in the schema:** Store `ISO 4217` codes (USD, GBP, EUR) or use a foreign key to a `currencies` dimension table. Never assume all values share one currency.
- **Conversion is a data problem, not a query problem:** If you must support multiple currencies, either normalize to one at ingestion time or store both original and converted values. Don't expect analysts to convert at query time.
- **This connects to:** data quality rules (e.g., salary must be positive), slowly-changing dimensions (exchange rates change), and documentation standards—put units in column descriptions and in your data dictionary.
