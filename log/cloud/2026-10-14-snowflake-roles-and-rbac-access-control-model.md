---
date: 2026-10-14
phase: cloud
topic: Snowflake roles and RBAC: access control model
---

# Snowflake roles and RBAC: access control model

*Cloud platforms and storage*

## Concept

Snowflake's role-based access control (RBAC) model manages who can do what with data and compute resources. Roles are containers of privileges; users are assigned to roles; privileges grant permissions on objects (tables, schemas, databases, warehouses). Without proper RBAC, you either over-share sensitive data or create bottlenecks where legitimate users can't access what they need.

RBAC matters most when your warehouse scales to multiple teams. A junior analyst shouldn't see salary data; a finance team shouldn't accidentally query the job postings database and burn $200 in compute. The cost impact is real: uncontrolled access often means uncontrolled queries—users running full table scans on tables they don't understand because they had overly broad SELECT privileges.

Without RBAC, you have two failure modes: security breaches (leaked PII or salary information) and runaway cost (no governance on who runs what queries). Snowflake charges per second of warehouse compute, so a single poorly-written query by someone without query-design training can cost money and block other users.

## Practice

**Problem:** Your analytics team has three sub-teams: recruiters (need to see job postings and locations), finance (need only salary data), and executives (need summaries only). Set up roles and grant minimal necessary privileges.

```sql
-- Create roles
CREATE ROLE recruiter_role;
CREATE ROLE finance_role;
CREATE ROLE executive_role;

-- Grant schema access
GRANT USAGE ON SCHEMA analytics TO ROLE recruiter_role;
GRANT USAGE ON SCHEMA analytics TO ROLE finance_role;
GRANT USAGE ON SCHEMA analytics TO ROLE executive_role;

-- Recruiters: SELECT on job_postings_fact (all columns)
GRANT SELECT ON TABLE analytics.job_postings_fact TO ROLE recruiter_role;

-- Finance: SELECT only on salary column (column-level privilege)
GRANT SELECT ON TABLE analytics.job_postings_fact (job_id, salary_year_avg) TO ROLE finance_role;

-- Executives: SELECT on a pre-aggregated summary view (not raw table)
CREATE VIEW analytics.salary_summary AS
  SELECT job_title_short, AVG(salary_year_avg) as avg_salary
  FROM analytics.job_postings_fact
  GROUP BY job_title_short;
GRANT SELECT ON VIEW analytics.salary_summary TO ROLE executive_role;

-- Assign users to roles
GRANT ROLE recruiter_role TO USER recruiter_alice;
GRANT ROLE finance_role TO USER finance_bob;
GRANT ROLE executive_role TO USER exec_carol;
```

## Notes

- **Warehouse privilege isolation:** Grant USAGE and OPERATE on specific warehouses per role. Finance running queries on the compute warehouse used by data scientists will contend for resources and inflate costs.

- **Inheritance chain:** Users inherit privileges through roles, and roles can be assigned to other roles (role hierarchy). Trace the chain when debugging "why can't I see this table?"—a missing USAGE on the parent schema blocks everything below it.

- **Column-level vs. row-level:** Snowflake's native RBAC handles columns well; row-level security (hiding specific records) requires dynamic data masking or row access policies, which are separate features and add latency.

- **Mistake: ACCOUNTADMIN for everything.** Tempting to give all users ACCOUNTADMIN to "just work," but you lose visibility into who modified what and introduce security risk. Use SYSADMIN for warehouse/object creation, SECURITYADMIN for users/roles.

- **Audit and cost attribution:** Pair RBAC with QUERY_HISTORY and warehouse resource monitors. You can see which role ran which query and charge back costs to teams, but only if roles are granular enough to distinguish business units.
