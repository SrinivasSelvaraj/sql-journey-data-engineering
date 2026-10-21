---
date: 2026-10-21
phase: reliability
topic: Network isolation and least privilege principles
---

# Network isolation and least privilege principles

*Quality, reliability and the professional layer*

## Concept

Network isolation and least privilege are the gatekeeping mechanisms that turn a working pipeline into a trustworthy one. Network isolation means restricting which systems can talk to which other systems—your ETL job shouldn't have an open door to every database, API, and file share in the organization. Least privilege means each process, user, and service account gets only the minimum permissions needed to do its job, nothing more.

Without these controls, a single compromised credential or misconfigured query becomes an organization-wide incident. A data engineer with production database write access also gets read access to payroll, health records, or customer PII they have no business touching. A pipeline that can reach any API endpoint becomes a pivot point for attackers. The difference between someone who "works" and someone who "owns" systems is accepting responsibility for what could go wrong if access is too broad.

In practice, this means database roles with specific table/column grants, service accounts tied to specific jobs (never shared), VPC rules that whitelist traffic, and audit logging that proves who accessed what when. It's overhead that feels unnecessary until your first security incident.

## Practice

**Problem:** Your job posting pipeline runs as a shared `analytics_user` account with SELECT/INSERT on the entire `jobs` schema. A junior engineer accidentally writes a script that uses this account to delete old job postings to "clean up." How do you prevent this while keeping the pipeline functional?

```sql
-- Create a read-only role for the ETL pipeline
CREATE ROLE jobs_etl_reader;
GRANT USAGE ON SCHEMA jobs TO jobs_etl_reader;
GRANT SELECT ON jobs.job_postings_fact TO jobs_etl_reader;

-- Create a service account specifically for this pipeline
CREATE USER etl_ingest_jobs_sa;
GRANT jobs_etl_reader TO etl_ingest_jobs_sa;

-- If the pipeline needs to write to a staging table only:
CREATE ROLE jobs_etl_writer;
GRANT USAGE ON SCHEMA jobs TO jobs_etl_writer;
GRANT INSERT ON jobs.job_postings_staging TO jobs_etl_writer;
GRANT SELECT ON jobs.job_postings_fact TO jobs_etl_writer;

-- Never grant ALTER, DROP, or DELETE
-- Assign the appropriate role based on the job's actual needs
ALTER USER etl_ingest_jobs_sa SET DEFAULT_ROLE = jobs_etl_reader;
```

## Notes

- **Role sprawl is real:** Creating too many fine-grained roles becomes unmaintainable. Start with function-based roles (reader, writer, admin) and split only when you have a concrete reason.
- **Service accounts are not optional:** Shared credentials mean shared blame and no audit trail. Each pipeline/job should have its own account, even if it costs more overhead.
- **Least privilege + monitoring:** Restrictive access is only effective if you log and alert on violations. A denied DELETE is useless if no one notices or responds to it.
- **Adjacent concepts:** This connects to secrets management (how the service account's password/token is stored and rotated), audit logging (proving compliance), and network ACLs (the infrastructure layer below the database).
- **Revisit on promotion:** When you move from writing one-off jobs to owning shared infrastructure, this becomes non-negotiable. It's the difference between "works for me" and "safe for production."
