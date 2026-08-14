---
date: 2026-08-14
phase: cloud
topic: CI/CD for data pipelines
---

# CI/CD for data pipelines

*Cloud platforms and storage*

## Concept

CI/CD for data pipelines automates testing, validation, and deployment of data transformations across environments (dev → staging → prod), catching errors before they reach production and corrupting downstream analytics. Without it, schema changes, logic bugs, and performance regressions slip through undetected—a slow query in production might run for hours before anyone notices, inflating cloud costs and delaying reports that stakeholders depend on.

In cloud platforms (BigQuery, Redshift, Snowflake), CI/CD becomes cost-critical: every failed transformation wastes compute, storage scans happen on stale or incorrect data, and there's no version control of *when* a query started costing 10x more. A robust pipeline includes automated data quality checks (row counts, null rates, freshness), cost monitoring alerts, and rollback procedures so a bad deploy doesn't burn budget before you catch it.

Think of it as the difference between shipping untested code to production and catching bugs in a staging environment first. For data, the blast radius is wider—a single slow query can cascade into incorrect dashboards, wasted infrastructure spend, and lost trust in your data team.

## Practice

**Problem:** Your `job_postings_fact` table grows daily. A recent change to filter only remote jobs (`job_work_from_home = TRUE`) significantly reduced row counts, but nobody validated whether downstream reports should shrink or whether this breaks SLA expectations. You need a CI/CD check that alerts if row count drops >30% from the previous day without explicit approval.

```sql
-- data_quality_check.sql (runs as part of CI pipeline)
WITH current_count AS (
  SELECT COUNT(*) as today_count
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE()
),
previous_count AS (
  SELECT COUNT(*) as yesterday_count
  FROM job_postings_fact
  WHERE job_posted_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
)
SELECT
  current_count.today_count,
  previous_count.yesterday_count,
  ROUND(100 * (1 - current_count.today_count / previous_count.yesterday_count), 2) as pct_change
FROM current_count, previous_count
HAVING pct_change > 30
  -- If this query returns rows, CI/CD blocks deployment and notifies team
```

## Notes

- **Cost blindness is the biggest trap:** Set up BigQuery/Redshift cost alerts *before* a rogue cartesian join scans your entire table. Query explain plans and slot usage should be reviewed in staging.
- **Data quality checks aren't optional:** Row count, freshness, null rates, and schema validation must run automatically on every deploy; manual spot-checks miss 80% of silent failures.
- **Version control your transformations:** dbt, Airflow DAGs, or stored procedures must live in Git with code review; "we fixed it in the database" is not a deployment strategy.
- **Staging environments matter:** A production-like staging schema (same size, same indexes) catches performance regressions that dev can't; querying a tiny sample misses real-world slowness.
- **Adjacent topics:** Query optimization (EXPLAIN, indexes), monitoring (cost dashboards, SLOs), and infrastructure-as-code (Terraform for warehouse config) all feed into a functional CI/CD loop.
