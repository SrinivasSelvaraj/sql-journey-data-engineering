---
date: 2026-08-24
phase: cloud
topic: Column masking, row filters and dynamic data masking
---

# Column masking, row filters and dynamic data masking

*Cloud platforms and storage*

## Concept

Column masking hides sensitive data at the column level (e.g., salary values, email addresses), while row filters restrict which records a user can see based on attributes or permissions. Dynamic data masking (DDM) applies these rules at query time without storing masked copies, reducing storage costs and keeping a single source of truth. This matters because unauthorized users should never see PII, salary data, or location info—yet legitimate analysts need clean datasets to work with. Without masking, you either deny access entirely (loses productivity), duplicate data into separate schemas (storage waste, sync problems), or rely on application logic (error-prone, slow).

In cloud platforms like Snowflake, BigQuery, and Redshift, DDM is baked into the query engine, so the filtering happens before results return to the user. The cost implication is subtle: a query that returns masked rows still scans the full dataset, so masking doesn't reduce compute time—but it does eliminate the need for ETL jobs that previously created separate "safe" tables. Row filters, however, *can* reduce scan cost if the platform pushes the filter into the storage layer early.

## Practice

**Problem:** Your organization has a `job_postings_fact` table. Recruiters need to see all columns for jobs in their region; finance analysts need to see salaries but only for approved postings; junior analysts should see job titles and locations only—no salaries, no work-from-home flags. Currently you maintain three separate tables and manual data loads.

```sql
-- Snowflake example using Dynamic Data Masking (DDM) + Row Access Policy (RAP)

-- 1. Mask salary column for non-finance users
CREATE MASKING POLICY salary_mask AS
  (val NUMBER) RETURNS NUMBER ->
  CASE 
    WHEN CURRENT_ROLE() IN ('FINANCE', 'ADMIN') THEN val
    ELSE NULL
  END;

ALTER TABLE job_postings_fact 
  MODIFY COLUMN salary_year_avg SET MASKING POLICY salary_mask;

-- 2. Mask location and work-from-home for junior analysts
CREATE MASKING POLICY junior_analyst_mask AS
  (val VARCHAR) RETURNS VARCHAR ->
  CASE 
    WHEN CURRENT_ROLE() IN ('SENIOR_ANALYST', 'ADMIN') THEN val
    ELSE 'REDACTED'
  END;

ALTER TABLE job_postings_fact 
  MODIFY COLUMN job_location SET MASKING POLICY junior_analyst_mask;

-- 3. Row filter: recruiters see only their region (stored in user context)
CREATE ROW ACCESS POLICY region_filter AS
  (region_col VARCHAR) RETURNS BOOLEAN ->
  CASE
    WHEN CURRENT_ROLE() = 'ADMIN' THEN TRUE
    WHEN CURRENT_ROLE() LIKE 'RECRUITER_%' 
      THEN region_col = CURRENT_USER_ATTRIBUTE('region')
    ELSE FALSE
  END;

ALTER TABLE job_postings_fact 
  ADD ROW ACCESS POLICY region_filter ON (job_location);

-- Result: same table, one query, role-based visibility
SELECT * FROM job_postings_fact;
-- Finance sees salaries, analysts see REDACTED, recruiters see only their region.
```

## Notes

- **Masking is transparent but not free:** query still scans all rows; the cost savings come from eliminating duplicate tables, not from reducing I/O.
- **Row filters can prevent full scans:** if your platform (Snowflake, BigQuery) pushes filters to storage, a recruiter querying one region may scan far fewer partitions—check query plans to confirm.
- **Masking policies are role-based, not user-based by default:** use `CURRENT_USER_ATTRIBUTE()` to tie masks to individual attributes (department, region, clearance level) rather than hard-coding roles.
- **Adjacent topics:** column-level encryption (different goal—protects data at rest), query result caching (can expose masked values if cache is shared—disable for sensitive columns), federated queries (masking may not propagate across linked systems).
- **Common mistake:** applying DDM *after* joins; if a masked column is joined before masking is applied, the policy may fail or leak data—apply policies to base tables before denormalization.
