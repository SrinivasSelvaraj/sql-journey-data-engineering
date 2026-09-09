---
date: 2026-09-09
phase: reliability
topic: RBAC vs ABAC for data access control
---

# RBAC vs ABAC for data access control

*Quality, reliability and the professional layer*

## Concept

**RBAC (Role-Based Access Control)** grants permissions based on job titles or predefined roles: a "data analyst" role gets read access to all tables, a "data engineer" role gets write access to staging tables. It's coarse-grained and easy to administer at scale, but inflexible—you can't restrict an analyst from seeing salary data without creating a new role.

**ABAC (Attribute-Based Access Control)** grants permissions based on attributes of the user, the resource, and the context: "allow read if user.department == 'finance' AND table.sensitivity == 'public' AND time.hour < 22". It's granular and adaptive, but requires infrastructure to evaluate policies at query time and careful design to avoid performance cliffs.

In data engineering, RBAC is where you start (it scales to hundreds of users), but ABAC is where you move when RBAC creates unsustainable role explosion. The moment you need different salary visibility rules for different teams, or time-based access to sensitive datasets, or column-level masking that changes by business unit, RBAC breaks. Without a policy layer, you either bloat roles, hardcode logic in views, or leak data.

## Practice

**Problem:** Your company has `job_postings_fact` with salary data. Finance analysts should see all columns. Hiring managers should see everything except `salary_year_avg`. Candidates (external users with your portal) should see only `job_id`, `job_title_short`, `job_location`, and `job_posted_date`—but only for jobs posted in the last 90 days with `job_work_from_home = true`. RBAC alone requires 3+ roles and view duplication. Build an ABAC solution.

```sql
-- Central policy table
CREATE TABLE access_policies (
  policy_id INT PRIMARY KEY,
  role_name VARCHAR,
  resource_name VARCHAR,
  allowed_columns VARCHAR[],
  row_filter VARCHAR,
  priority INT
);

INSERT INTO access_policies VALUES
  (1, 'finance_analyst', 'job_postings_fact', 
   ARRAY['job_id', 'job_title_short', 'salary_year_avg', 'job_work_from_home', 'job_posted_date', 'job_location'],
   'TRUE', 100),
  (2, 'hiring_manager', 'job_postings_fact',
   ARRAY['job_id', 'job_title_short', 'job_work_from_home', 'job_posted_date', 'job_location'],
   'TRUE', 100),
  (3, 'external_candidate', 'job_postings_fact',
   ARRAY['job_id', 'job_title_short', 'job_location', 'job_posted_date'],
   'job_work_from_home = true AND job_posted_date > NOW() - INTERVAL 90 DAY', 100);

-- View that applies policy at query time
CREATE VIEW job_postings_secure AS
SELECT 
  CASE WHEN 'job_id' = ANY(ap.allowed_columns) THEN job_id ELSE NULL END as job_id,
  CASE WHEN 'job_title_short' = ANY(ap.allowed_columns) THEN job_title_short ELSE NULL END as job_title_short,
  CASE WHEN 'salary_year_avg' = ANY(ap.allowed_columns) THEN salary_year_avg ELSE NULL END as salary_year_avg,
  CASE WHEN 'job_work_from_home' = ANY(ap.allowed_columns) THEN job_work_from_home ELSE NULL END as job_work_from_home,
  CASE WHEN 'job_posted_date' = ANY(ap.allowed_columns) THEN job_posted_date ELSE NULL END as job_posted_date,
  CASE WHEN 'job_location' = ANY(ap.allowed_columns) THEN job_location ELSE NULL END as job_location
FROM job_postings_fact jpf
CROSS JOIN (SELECT * FROM access_policies WHERE role_name = CURRENT_USER) ap
WHERE ap.resource_name = 'job_postings_fact'
  AND (ap.row_filter = 'TRUE' OR jpf.* :: TEXT LIKE '%' || ap.row_filter || '%')
ORDER BY ap.priority DESC
LIMIT 1;
```

## Notes

- **Role explosion:** RBAC works until you have 15+ roles; then maintenance becomes a compliance liability. ABAC trades operational complexity (policy evaluation) for administrative simplicity.
- **Performance cost:** Every ABAC query must evaluate attributes. Use row-level security (RLS) in PostgreSQL or column masking in Snowflake rather than expensive view logic. Push policy down to the database engine.
- **Adjacent concepts:** connects to data governance (who owns the policy table?), column-level masking, time-decay policies, and PII tagging. Also touches on audit logging—ABAC denials must be logged.
- **
