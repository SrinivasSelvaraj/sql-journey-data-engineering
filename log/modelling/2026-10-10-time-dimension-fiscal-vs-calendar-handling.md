---
date: 2026-10-10
phase: modelling
topic: Time dimension: fiscal vs calendar handling
---

# Time dimension: fiscal vs calendar handling

*Data modelling and warehousing*

## Concept

Most business users think in fiscal years (Apr–Mar, Jul–Jun, Oct–Sep) while data is recorded in calendar years (Jan–Dec). Without explicit dimension design, the same metric produces different answers depending on which timeframe someone queries—breeding confusion and double-counting.

The fix is a **time dimension table** that maps every date to both calendar *and* fiscal attributes. A single `job_posted_date` column should link to a `dim_date` table carrying `calendar_year`, `calendar_month`, `fiscal_year`, `fiscal_quarter`, `fiscal_month`, and fiscal start/end flags. This makes it impossible to misinterpret what "Q3 2024" means.

Without this, analysts either write fragile CASE statements in every query or ask you to clarify. With it, column names are self-documenting and business logic lives in one place—the dimension—not scattered across reports.

## Practice

**Problem:** Your finance team needs Q3 hiring trends (Jul–Sep) but accounting reports on fiscal year (Oct–Sep). A naive grouping by `EXTRACT(QUARTER FROM job_posted_date)` will silently misalign the two views.

```sql
-- Create time dimension (run once)
CREATE TABLE dim_date AS
SELECT 
  date_key,
  full_date,
  EXTRACT(YEAR FROM full_date) AS calendar_year,
  EXTRACT(QUARTER FROM full_date) AS calendar_quarter,
  CASE 
    WHEN EXTRACT(MONTH FROM full_date) >= 10 THEN EXTRACT(YEAR FROM full_date) + 1
    ELSE EXTRACT(YEAR FROM full_date)
  END AS fiscal_year,
  CASE 
    WHEN EXTRACT(MONTH FROM full_date) >= 10 THEN 1
    WHEN EXTRACT(MONTH FROM full_date) >= 7 THEN 3
    WHEN EXTRACT(MONTH FROM full_date) >= 4 THEN 2
    ELSE 4
  END AS fiscal_quarter
FROM (SELECT generate_series('2020-01-01'::date, '2025-12-31'::date, '1 day'::interval)::date AS full_date);

-- Query now uses fiscal dimension, not raw date math
SELECT 
  d.fiscal_year,
  d.fiscal_quarter,
  COUNT(*) AS postings
FROM job_postings_fact f
JOIN dim_date d ON f.job_posted_date = d.full_date
WHERE d.fiscal_year = 2024
GROUP BY d.fiscal_year, d.fiscal_quarter
ORDER BY d.fiscal_quarter;
```

## Notes

- **CASE logic in queries is a red flag:** If you see `WHEN MONTH >= 10` in three different reports, the dimension table belongs in the warehouse, not the BI tool.
- **Fiscal calendars vary by company:** Confirm the offset (Oct vs. Jul vs. Apr start) before building. Hard-coding the wrong one silently breaks year-over-year comparisons.
- **Slowly Changing Dimensions (SCD):** Fiscal calendars *do* change (company acquisition, restructure). Plan version control on `dim_date` if you need historical accuracy.
- **Adjacent: grain and conformation:** Time dimension must be at the finest grain you'll ever filter on (usually day). All fact tables must join to the same dimension to ensure metrics are comparable.
- **Revisit: holidays, working days, and "fiscal days elapsed"** are useful extensions; consider adding `is_business_day`, `days_in_fiscal_period`, and `fiscal_day_of_year` for forecasting queries.
