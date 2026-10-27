---
date: 2026-10-27
phase: modelling
topic: Date dimension design and fiscal calendars
---

# Date dimension design and fiscal calendars

*Data modelling and warehousing*

## Concept

A date dimension is a dedicated table that stores every possible date alongside pre-calculated attributes—day of week, month, quarter, fiscal period, holiday flags—so analysts query business logic once, not repeatedly. Fiscal calendars matter because most organizations don't run January–December; retail peaks October–December, universities operate August–July, and financial institutions may close books March 31. Without a date dimension, every query recalculates "is this a holiday?" or "which fiscal quarter?" differently, creating inconsistent reporting and hidden bugs when someone forgets leap years or daylight saving time.

The cost of skipping this: a dashboard shows Q1 revenue one way, a data analyst calculates it another, and executives lose trust in the warehouse. Worse, fiscal logic bleeds into fact tables and business logic, making the schema opaque—new team members don't know if `job_posted_date` is UTC or local time, whether it includes weekends, or what "fiscal Q2" really means for job postings.

## Practice

**Problem:** You're building a job postings dashboard and need to compare hiring volume by fiscal quarter. The business uses a fiscal year April–March (April 1 = FY start). Currently, you filter `job_posted_date` directly, but different teams calculate quarters differently.

**Solution:**

```sql
-- Create a date dimension with fiscal calendar baked in
CREATE TABLE date_dim (
  date_id INT PRIMARY KEY,
  calendar_date DATE UNIQUE,
  day_of_week VARCHAR(10),
  day_of_month INT,
  month_num INT,
  calendar_quarter INT,
  calendar_year INT,
  fiscal_quarter INT,
  fiscal_year INT,
  is_weekend BOOLEAN,
  is_holiday BOOLEAN,
  holiday_name VARCHAR(50)
);

-- Now the fact table references the dimension
ALTER TABLE job_postings_fact ADD COLUMN date_id INT;

-- Query becomes simple and consistent
SELECT 
  d.fiscal_year,
  d.fiscal_quarter,
  COUNT(*) as job_count
FROM job_postings_fact f
JOIN date_dim d ON f.date_id = d.date_id
WHERE d.fiscal_year = 2024
GROUP BY d.fiscal_year, d.fiscal_quarter
ORDER BY d.fiscal_quarter;
```

## Notes

- **Fiscal offset trap:** April–March fiscal year means months 4–12 of calendar year 2024 belong to FY2024, but months 1–3 belong to FY2024. Calculate `fiscal_year = CASE WHEN MONTH(date) >= 4 THEN YEAR(date) + 1 ELSE YEAR(date) END` carefully.
- **Pre-load the dimension:** Generate dates for 50+ years at warehouse initialization; date dimensions rarely change and are small enough to materialize fully (18,250 rows for 50 years).
- **Holiday flags are localized:** A US holiday dimension is useless for a European team; either maintain multiple holiday columns per region or create a separate holiday bridge table.
- **Connects to:** slowly changing dimensions (SCD Type 2) if fiscal calendar rules change, and conformed dimensions when multiple fact tables share the same date_dim.
- **Revisit:** time zones and `GETUTCDATE()` vs local `GETDATE()`; if job postings come from global sources, standardize to UTC in the fact table and add a timezone_id to the dimension for local reporting.
