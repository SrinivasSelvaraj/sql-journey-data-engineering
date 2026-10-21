---
date: 2026-10-21
phase: reliability
topic: Security scanning in CI/CD pipelines
---

# Security scanning in CI/CD pipelines

*Quality, reliability and the professional layer*

## Concept

Security scanning in CI/CD detects vulnerabilities before code reaches production—secrets in commits, outdated dependencies with known CVEs, infrastructure-as-code misconfigurations, and SQL injection risks in queries. It's the difference between shipping fast and shipping safely. Without it, you discover credential leaks after they're live, run databases on unpatched versions with public exploits, or push infrastructure that exposes data.

In data pipelines specifically, security scanning catches hardcoded passwords in transformation logic, SQL queries vulnerable to injection (especially when building dynamic queries), and overpermissioned cloud credentials. A single leaked AWS key in a GitHub commit can cost thousands in minutes. A staging table query that concatenates untrusted input invites injection attacks that corrupt or expose data.

The professional layer owns security as a first-class requirement, not an afterthought. This means automated scanning on every commit, blocking merges when high-severity issues surface, and treating security failures like any other production incident.

## Practice

**Problem:** Your job posting pipeline accepts a location filter from an API request and builds a query dynamically. The current code is vulnerable to SQL injection. Write a secure version.

```sql
-- INSECURE (vulnerable to injection)
-- SELECT * FROM job_postings_fact 
-- WHERE job_location = '${user_input}'

-- SECURE (using parameterized query)
DECLARE @location NVARCHAR(MAX) = ?;
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE job_location = @location
AND job_posted_date >= CAST(GETDATE() - 30 AS DATE);
```

The parameterized approach treats user input as data, not executable SQL. Bind the parameter at runtime in your pipeline code (e.g., SQLAlchemy's `text()` with bound parameters, or your ORM's native parameterization).

## Notes

- **Secrets in code**: Use secret managers (AWS Secrets Manager, HashiCorp Vault, GitHub Secrets) and scan for common patterns (`aws_access_key`, `password=`, `api_key`). Pre-commit hooks catch this before it reaches the repo.
- **Dependency scanning**: Tools like Snyk, Dependabot, or OWASP Dependency-Check flag libraries with known CVEs. Pin versions in CI and block upgrades to vulnerable patches.
- **IaC scanning**: Terraform/CloudFormation code often hardcodes credentials or opens security groups too wide. Checkov and TFLint catch these at plan time, not after deployment.
- **Connected to**: data governance (who accesses what), infrastructure permissions (least privilege), and incident response (what's your playbook when a key leaks?).
- **Revisit**: the difference between static and dynamic scanning; how to balance security gates with velocity; what severity levels warrant blocking a merge.
