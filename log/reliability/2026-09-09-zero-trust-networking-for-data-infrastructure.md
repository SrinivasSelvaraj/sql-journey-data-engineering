---
date: 2026-09-09
phase: reliability
topic: Zero trust networking for data infrastructure
---

# Zero trust networking for data infrastructure

*Quality, reliability and the professional layer*

## Concept

Zero trust networking means verifying every access request to your data infrastructure—no exceptions for "internal" users, no implicit trust based on network location. In data engineering, this translates to: every service, job, user, and script that touches your warehouse or data lake must authenticate and be authorized explicitly, with that trust continuously validated.

This matters because data pipelines are organizational arteries. A compromised analyst credential, a misconfigured service account, or lateral movement from a breached application can silently exfiltrate or corrupt your entire fact table. Without zero trust, you discover the breach weeks later in audit logs. With it, you catch the unauthorized SELECT on your revenue table in seconds.

What breaks without it: pipeline access control becomes theater (firewall rules and VPCs create the illusion of safety), audit trails become noise (you can't distinguish legitimate from malicious queries), and ownership becomes fiction (if anyone on the network can query anything, nobody is responsible for data quality or governance).

## Practice

**Problem:** Your `job_postings_fact` table contains salary data. Your analytics team should read it; your ETL should insert; your finance team should read only US-based rows. Today, anyone with a database login can see everything. Design a zero trust enforcement.

```sql
-- Create role-based access control with row-level security

-- 1. Base roles (authentication)
CREATE ROLE analytics_read_only;
CREATE ROLE etl_writer;
CREATE ROLE finance_restricted;

-- 2. Grant table permissions (authorization)
GRANT SELECT ON job_postings_fact TO analytics_read_only;
GRANT SELECT, INSERT, UPDATE ON job_postings_fact TO etl_writer;
GRANT SELECT ON job_postings_fact TO finance_restricted;

-- 3. Enforce row-level security policy
CREATE POLICY finance_us_only ON job_postings_fact
  AS RESTRICTIVE
  FOR SELECT
  TO finance_restricted
  USING (job_location LIKE '%US%');

-- 4. Assign users to roles (minimal privilege)
GRANT analytics_read_only TO analyst_sarah;
GRANT etl_writer TO data_pipeline_service_account;
GRANT finance_restricted TO finance_user_john;

-- 5. Enable audit logging (continuous verification)
ALTER TABLE job_postings_fact ENABLE ROW LEVEL SECURITY;
SELECT * FROM audit_log WHERE table_name = 'job_postings_fact' 
  ORDER BY query_timestamp DESC LIMIT 100;
```

## Notes

- **Mistake:** Granting roles to groups instead of individuals. Group membership drifts; you lose audit trail of *who* did what. Assign roles directly and rotate service account credentials quarterly.
- **Mistake:** Assuming network isolation (private subnets, security groups) replaces authentication. They're defense layers; zero trust sits at the query level.
- **Adjacent:** Connects tightly to secrets management (where do service accounts store their credentials?) and observability (can you detect anomalous query patterns in real time?).
- **Revisit:** Row-level security policies often have performance cost; profile your filters. For large fact tables, consider partitioning by authorization boundary instead.
- **Ownership signal:** If you can list every principal with access to a table and explain *why* in 30 seconds, you're practicing zero trust. If you can't, you don't own the pipeline.
