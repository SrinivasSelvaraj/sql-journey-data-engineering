---
date: 2026-08-23
phase: cloud
topic: Snowflake data sharing and marketplace
---

# Snowflake data sharing and marketplace

*Cloud platforms and storage*

## Concept

Snowflake Data Sharing enables zero-copy sharing of live tables between accounts without duplicating data, while Snowflake Marketplace lets providers publish datasets for discovery and consumption. Data Sharing is governed at the database or schema level through shares, which are read-only views into the provider's account; the consumer sees real-time data without ETL delays or storage overhead. This matters because it eliminates the traditional data warehouse bottleneck: instead of exporting, transforming, and loading external datasets, analysts and downstream teams access curated tables directly.

What breaks without it: you resort to nightly CSV dumps or API pulls, introducing staleness, storage redundancy, and operational friction. Marketplace adoption matters for monetization; sharing matters for internal cost allocation and governance. Both rely on Snowflake's network policies, role-based access control (RBAC), and query result caching to prevent runaway costs when consumers run expensive queries against shared data.

## Practice

**Problem:** You maintain `job_postings_fact` and want to share salary insights with a partner organization without letting them see the raw table. You need to control which columns they access and filter data by job location.

```sql
-- Provider account: create a share and add the curated view
CREATE SHARE job_insights_partner;

CREATE VIEW job_insights_public AS
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date
  FROM job_postings_fact
  WHERE job_location IN ('United States', 'Remote');

GRANT USAGE ON SCHEMA public TO SHARE job_insights_partner;
GRANT SELECT ON VIEW job_insights_public TO SHARE job_insights_partner;
ALTER SHARE job_insights_partner ADD ACCOUNTS = xyz123.us_east_1;

-- Consumer account: create database from share
CREATE DATABASE job_insights FROM SHARE provider_account.job_insights_partner;

SELECT AVG(salary_year_avg) as avg_salary
FROM job_insights.public.job_insights_public
WHERE job_work_from_home = TRUE;
```

## Notes

- **Cost hidden in shares:** consumers' query compute is billed to *their* account, not the provider. Monitor via `QUERY_HISTORY` and set warehouse size limits to prevent surprise bills.
- **Marketplace vs. internal shares:** Marketplace requires publishing to a listing (discoverable, monetizable); direct shares are account-to-account (faster, quieter). Choose based on audience scope.
- **Zero-copy doesn't mean free:** shared objects still consume storage and time-travel history. Views add query overhead; use materialized views or dynamic tables in consumer accounts if latency matters.
- **RBAC + shares:** shares operate at database level; further row/column masking requires role-based policies or secure views in consumer accounts.
- **Adjacent: query optimization.** Slow queries on shared data often stem from missing statistics or lack of clustering keys. Revisit pruning strategy and consider secondary indexing in high-cardinality scenarios.
