---
date: 2026-08-17
phase: reliability
topic: Access control and row level security
---

# Access control and row level security

*Quality, reliability and the professional layer*

## Concept

Access control and row-level security (RLS) enforce who can see what data at query time, not just at the application layer. Without it, a junior analyst can query salary data for executives, a contractor sees all job locations including confidential remote roles, or a regional manager accidentally returns results for markets they don't own. This is different from table-level permissions (which control whether you can access a table at all) — RLS filters *rows* based on identity, role, or context, ensuring the same query returns different results for different users.

RLS becomes critical the moment your warehouse serves multiple stakeholders with conflicting data visibility needs. A single job_postings_fact table might be accessed by recruiters (who need full data), hiring managers (filtered to their region), and executives (aggregated only). Without RLS, you either build separate tables, embed logic in every application query, or expose everything. The first approach doesn't scale; the second is fragile and repeated; the third is a compliance liability. RLS pushes the enforcement into the data layer where it's centralized, auditable, and survives application changes.

## Practice

**Problem:** Your job_postings_fact table is accessed by regional hiring managers and a central recruitment team. A manager in the Northeast should only see postings with job_location matching their region, but the recruitment team needs all rows. You can't create separate tables. How do you enforce this at query time?

```sql
-- Step 1: Create a simple access control table
CREATE TABLE hiring_manager_regions (
  manager_id VARCHAR,
  allowed_region VARCHAR
);

INSERT INTO hiring_manager_regions VALUES
  ('mgr_001', 'Northeast'),
  ('mgr_002', 'Southeast'),
  ('recruiter_all', NULL);  -- NULL means unrestricted

-- Step 2: Create a view that applies row-level filtering
CREATE VIEW job_postings_secured AS
SELECT j.*
FROM job_postings_fact j
WHERE j.job_location LIKE CONCAT(
  COALESCE(
    (SELECT allowed_region FROM hiring_manager_regions 
     WHERE manager_id = CURRENT_USER LIMIT 1),
    '%'
  ), '%'
);

-- Step 3: Users query the view instead of the table
-- Manager in Northeast sees only Northeast postings
SELECT job_title_short, salary_year_avg FROM job_postings_secured
WHERE job_posted_date > '2024-01-01';

-- Step 4: (Stronger approach) Use database-native RLS if available (Postgres example)
ALTER TABLE job_postings_fact ENABLE ROW LEVEL SECURITY;

CREATE POLICY job_location_policy ON job_postings_fact
  FOR SELECT
  USING (
    job_location LIKE CONCAT(
      COALESCE(
        (SELECT allowed_region FROM hiring_manager_regions 
         WHERE manager_id = CURRENT_USER LIMIT 1),
        '%'
      ), '%'
    )
  );
```

## Notes

- **CURRENT_USER vs application context:** Many teams pass user identity via application code rather than relying on the database user. This is weaker — use session variables or JWT claims if your database supports them, and validate them server-side before setting.
- **Testing RLS is tedious and often skipped.** You must test as multiple users/roles, not just the admin account. Automated row-count tests per role reveal silent permission creep.
- **RLS + aggregation is tricky.** SUM(salary) filtered per region looks right until someone requests an org-wide salary report and gets nonsense. Document what aggregations are safe and which require a bypass role.
- **Connects to:** data lineage (audit who saw what), masking (hiding values, not rows), and schema design (whether to denormalize region or force a join every query).
- **Revisit:** the cost of row filtering at scale — some databases push this to query optimization time, others evaluate it row-by-row. Profile your largest tables before rolling out to production.
