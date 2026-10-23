---
date: 2026-10-23
phase: sql
topic: Temporal queries and time-travel syntax
---

# Temporal queries and time-travel syntax

*SQL for analytics and engineering*

## Concept

Temporal queries and time-travel syntax allow you to query data *as it existed at a specific point in the past*, rather than only accessing the current state. In systems like Snowflake (`AT | BEFORE`), BigQuery (snapshots), or Iceberg tables, you can reconstruct historical snapshots without maintaining separate archive tables. This is critical for analytics when you need to know "what was the salary distribution *when* a job was posted?" or audit "what changed between two dates?"—questions that raw current data cannot answer.

The problem it solves: analytical questions often require temporal joins (matching a fact to its context at a specific moment) and data reconciliation (detecting when dimensions changed). Without time-travel, you either lose historical context, materialize expensive snapshots, or maintain complex SCD (slowly changing dimensions) logic manually. With it, the system manages versioning transparently.

What breaks without it: you cannot correctly answer "how many jobs offered remote work *on the day they were posted*?" if the `job_work_from_home` field is updated retroactively. You also cannot join a fact table to a dimension as it existed on a past date—you only see the latest state, introducing silent correctness errors in analytics.

## Practice

**Problem:** Write a query that shows the salary and remote-work status of jobs *as they were on the day they were posted*, then compare against today's snapshot. Assume a Snowflake table `job_postings_fact` with versioning enabled.

```sql
-- Historical snapshot: state on job_posted_date
SELECT 
  job_id,
  job_title_short,
  salary_year_avg AS salary_at_post,
  job_work_from_home AS remote_at_post,
  job_posted_date
FROM job_postings_fact
  AT (TIMESTAMP => job_posted_date)
WHERE job_posted_date >= '2024-01-01'

UNION ALL

-- Current snapshot: state today
SELECT 
  job_id,
  job_title_short,
  salary_year_avg AS salary_today,
  job_work_from_home AS remote_today,
  CURRENT_DATE
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'

ORDER BY job_id, job_posted_date;
```

*Alternative (if time-travel unavailable):* materialize a daily snapshot table via a scheduled task, or use a change-data-capture (CDC) feed to reconstruct state.

## Notes

- **Timestamp precision matters:** `AT (TIMESTAMP)` requires exact timestamp; if you use `AT (DATE)`, the system may resolve to start-of-day UTC, causing off-by-one errors across timezones.
- **Performance trade-off:** time-travel queries scan version history, not just current data. They are faster than manual SCD joins but slower than querying a denormalized snapshot. Profile before relying on them for real-time dashboards.
- **Connects to:** slowly changing dimensions (SCD Type 2), bitemporal modeling, event sourcing, and CDC pipelines. Time-travel is the managed alternative.
- **Common mistake:** assuming `AT (TIMESTAMP => column_name)` evaluates the column per row—it doesn't. The timestamp must be a literal or query-time constant. Use a self-join or `LATERAL` subquery if you need per-row lookups.
- **Revisit:** data retention policies (Snowflake keeps versions for 1–90 days by default), how to query across schema changes, and when to materialize snapshots instead of relying on time-travel for compliance audits.
