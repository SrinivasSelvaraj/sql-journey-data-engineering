---
date: 2026-08-13
phase: cloud
topic: IAM: roles, policies and least privilege
---

# IAM: roles, policies and least privilege

*Cloud platforms and storage*

## Concept

IAM (Identity and Access Management) controls *who* can do *what* on cloud resources—roles define job functions, policies attach permissions to those roles, and least privilege means granting only the minimum access needed. In data engineering, this directly affects query costs and security: a runaway service account with `*:*` permissions might spin up expensive compute clusters or read data you didn't intend to scan, while overly restricted credentials cause mysterious "permission denied" failures during midnight ETL runs. Without proper IAM, you lose the ability to audit who ran that billion-row scan, isolate blast radius when credentials leak, and enforce separation between dev/prod environments—turning debugging into a guessing game while your cloud bill climbs.

## Practice

**Problem:** You have a data analytics team that needs to query `job_postings_fact` for salary analysis, but currently they share a single service account with full database access. You need to create a read-only role that allows them to query only salary and location columns, blocking access to job IDs and post dates (which are sensitive for competitive reasons).

```sql
-- Create a read-only role with column-level security
CREATE ROLE analytics_reader;

GRANT SELECT (job_title_short, salary_year_avg, job_location) 
  ON job_postings_fact 
  TO analytics_reader;

-- Assign the role to the analytics team's service account
GRANT analytics_reader TO 'analytics-team-sa@project.iam.gserviceaccount.com';

-- Verify permissions (this query should work)
SELECT job_title_short, salary_year_avg, job_location 
FROM job_postings_fact 
WHERE salary_year_avg > 100000;

-- This query should be denied
SELECT job_id, job_posted_date FROM job_postings_fact;
```

## Notes

- **Common mistake:** Granting `ADMIN` or `EDITOR` roles to service accounts "just to get it working," then forgetting to revoke them—exponential blast radius over time.
- **Adjacent topic:** Cost allocation and chargeback require IAM audit logs; you can't charge back a query to the right team if you don't know which principal ran it.
- **Revisit regularly:** Permissions creep; audit role assignments quarterly and remove access when team members leave or switch projects.
- **Separate dev/prod:** Use different service accounts and IAM policies for dev and production environments to prevent a test query from affecting live dashboards.
- **Policy as code:** Store IAM policies in version control (Terraform, CloudFormation) alongside your data pipeline code so permission changes are reviewed and reversible.
