---
date: 2026-09-03
phase: cloud
topic: Snowflake: Dynamic Table refresh and direct data sharing
---

# Snowflake: Dynamic Table refresh and direct data sharing

*Cloud platforms and storage*

## Concept

A **Dynamic Table** in Snowflake is a managed table that automatically refreshes on a schedule (typically every 1–24 hours), executing a SQL query to materialize results. Unlike a view, it stores data physically, eliminating query overhead for consumers—you pay for compute at refresh time, not at read time. This is critical when you have expensive transformations (JOINs, aggregations, window functions) queried repeatedly by many users or dashboards.

**Direct Data Sharing** lets you share Dynamic Tables (or regular tables) across Snowflake accounts without copying data; the consumer queries your table in-place using their compute, and you see consumption metrics in your account. This matters because it decouples storage costs from sharing—you don't duplicate 100GB to share with five teams. However, if your Dynamic Table refresh frequency is too aggressive (e.g., every 15 minutes for a table queried once daily), you're wasting compute dollars on unnecessary refreshes.

Breaking without this: if you materialize nothing and 50 BI tools run the same complex transformation query, you burn compute 50 times per query cycle. If you share via copy instead of direct sharing, you duplicate storage and lose visibility into downstream consumption patterns, making cost allocation opaque.

## Practice

**Problem:** You're asked to create a "daily high-paying remote jobs summary" consumed by three different Slack bots and a dashboard. The raw `job_postings_fact` table has 2M rows and grows daily. A simple view would require all consumers to re-run the same aggregation query each time they refresh.

```sql
CREATE DYNAMIC TABLE daily_remote_high_pay_summary
TARGET_LAG = '1 day'
AS
SELECT 
    job_posted_date,
    job_title_short,
    COUNT(DISTINCT job_id) as job_count,
    ROUND(AVG(salary_year_avg), 2) as avg_salary,
    ROUND(MAX(salary_year_avg), 0) as max_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
    AND salary_year_avg > 100000
    AND job_posted_date >= CURRENT_DATE - 30
GROUP BY job_posted_date, job_title_short
ORDER BY job_posted_date DESC, avg_salary DESC;

-- Share to partner account
CREATE SHARE job_analytics_share;
GRANT SELECT ON DYNAMIC TABLE daily_remote_high_pay_summary TO SHARE job_analytics_share;
ALTER SHARE job_analytics_share ADD ACCOUNTS = 'partner_account_name';
```

The Dynamic Table refreshes once daily (compute cost is fixed), and each consumer queries the materialized result (zero transformation cost). Direct sharing means your partner doesn't store a copy and you can see refresh lineage in `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`.

## Notes

- **Refresh lag vs. staleness trade-off:** A 1-hour TARGET_LAG costs 24× more than 1-day, but 1-day means your data is always at least 24h old. Audit your actual query frequency before choosing.
- **Clustering keys matter:** Dynamic Tables inherit clustering from their source tables; if `job_postings_fact` is poorly clustered by `job_posted_date`, the refresh scans the whole table even if only yesterday's rows changed.
- **Consumption shows up differently:** Direct shares consume the *consumer's* compute quota when they query, but the *provider's* Dynamic Table refresh cost is separate—track both in `QUERY_HISTORY.WAREHOUSE_NAME` to avoid surprise bills.
- **Adjacent topic:** Iceberg tables and native change data capture (CDC) provide row-level lineage; combine with Dynamic Tables for incrementally refreshing tables that only process deltas, not full scans.
- **Revisit:** Understand `SNOWFLAKE.ACCOUNT_USAGE.DYNAMIC_TABLE_*` views to monitor refresh duration and detect slow refreshes before they cascade costs; set up alerts if refresh time exceeds SLA.
