---
date: 2026-08-14
phase: cloud
topic: Multi-environment setup: dev, staging, prod
---

# Multi-environment setup: dev, staging, prod

*Cloud platforms and storage*

## Concept

A multi-environment setup isolates dev, staging, and prod into separate cloud resources (databases, storage buckets, compute clusters) so that testing and experimentation don't corrupt production data or inflate your bill. Without this separation, a runaway query in dev can drain your budget, a schema change can break live dashboards, and you have no safe place to test breaking changes before they affect users.

The key is that each environment should have its own dataset (or a subset for non-prod), its own service accounts with minimal necessary permissions, and separate cost tracking so you can see exactly which environment is expensive. This also enables you to use production-realistic data in staging without exposing it, and to run aggressive optimizations in dev without fear.

## Practice

**Problem:** You have a query that works in dev but runs for 15 minutes in prod, costing $50 per execution. You don't know if it's the data volume, a missing index, or a changed table schema—because you never tested against prod-sized data.

```sql
-- dev environment setup (small sample)
CREATE SCHEMA dev_analytics;
CREATE TABLE dev_analytics.job_postings_fact AS
SELECT * FROM prod_analytics.job_postings_fact 
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
LIMIT 100000;

-- staging environment setup (full schema, full volume)
CREATE SCHEMA staging_analytics;
CREATE TABLE staging_analytics.job_postings_fact AS
SELECT * FROM prod_analytics.job_postings_fact 
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY;

-- Test expensive query in staging first
EXPLAIN ANALYZE
SELECT job_location, AVG(salary_year_avg) as avg_salary, COUNT(*) as count
FROM staging_analytics.job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY job_location
ORDER BY avg_salary DESC;

-- Only deploy optimized query to prod after validation
CREATE INDEX idx_job_postings_wfh_location 
ON prod_analytics.job_postings_fact(job_work_from_home, job_location);
```

## Notes

- **Cost isolation trap:** Share the same database across dev/staging/prod and you can't distinguish which environment is bleeding money; always use separate projects or schemas with separate billing.
- **Data freshness vs. privacy:** Staging should use recent (ideally yesterday's) prod data for realistic testing, but anonymize or subset PII before copying down from production.
- **Permission creep:** Dev users often get prod read access "just to check something"—instead, automate a nightly refresh of prod data into staging and revoke direct prod access.
- **Connects to:** CI/CD pipelines (auto-deploy to staging/prod), data masking/PII handling, monitoring and alerting (detect which env is slow), and infrastructure-as-code (Terraform/CloudFormation to spin up identical envs).
- **Revisit when:** Adding a new data source, after a cost spike, or when onboarding a new analyst who has "broken" something in the past—use it as a teaching moment about environment boundaries.
