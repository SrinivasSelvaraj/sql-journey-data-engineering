---
date: 2026-10-03
phase: sql
topic: Statistics staleness and query plan instability
---

# Statistics staleness and query plan instability

*SQL for analytics and engineering*

## Concept

Statistics staleness occurs when a database's cost optimizer relies on outdated metadata about table size, distribution, and cardinality. When actual data diverges significantly from recorded statistics—due to bulk inserts, deletes, or schema changes—the query planner makes poor decisions: choosing full table scans over index seeks, nested-loop joins over hash joins, or inefficient join ordering. This is particularly acute in analytics pipelines where large ETL operations load fresh data nightly but statistics aren't refreshed, causing identical queries to flip between fast and slow execution.

Query plan instability compounds this: the same query may execute in 200ms one hour and 45 seconds the next, with no code change. This unpredictability breaks SLA commitments, makes debugging harder, and forces engineers to over-provision resources. In production analytics, you often can't simply rerun a query—dashboards timeout, users get stale results, and batch jobs fail their windows.

Addressing this requires two levers: explicitly refreshing statistics after major data mutations (ANALYZE, REFRESH STATISTICS depending on your database), and writing robust SQL that doesn't rely on the optimizer making a single perfect choice. This means avoiding extreme cardinality estimates (e.g., filtering before joining large tables) and structuring logic so reasonable plans all perform acceptably.

## Practice

**Problem:** You're building a daily report on high-paying remote jobs. The job_postings_fact table receives 50k new rows each morning. Your query filters for jobs posted today, salary over $150k, and remote-eligible roles. It ran in 300ms yesterday but takes 45 seconds today. Statistics were last refreshed a week ago. Write SQL that mitigates staleness risk and show the statistics refresh command.

```sql
-- Refresh statistics after ETL completes
ANALYZE TABLE job_postings_fact COMPUTE STATISTICS;
-- or in Snowflake: ALTER TABLE job_postings_fact REFRESH;

-- Write robust query: filter early, avoid cardinality surprises
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE()  -- Filter first: reduces rows early
  AND job_work_from_home = TRUE          -- Selective predicate
  AND salary_year_avg >= 150000          -- Avoids relying on stale range stats
ORDER BY salary_year_avg DESC
LIMIT 100;

-- If joining: push filters down before the join to reduce cardinality upstream
SELECT 
  p.job_id,
  p.job_title_short,
  p.salary_year_avg
FROM job_postings_fact p
INNER JOIN (
  -- Subquery reduces size before join, lessens impact of stale stats on join selectivity
  SELECT job_id FROM job_postings_fact 
  WHERE job_posted_date = CURRENT_DATE()
) recent ON p.job_id = recent.job_id
WHERE p.job_work_from_home = TRUE
  AND p.salary_year_avg >= 150000;
```

## Notes

- **Stale stats ≠ wrong results**, only wrong *plans*. Data consistency isn't at risk; performance is. Test correctness separately from performance.
- **Refresh timing matters**: schedule ANALYZE immediately after ETL ingestion, not during peak query hours. In Snowflake/BigQuery, auto-refresh is often enabled; in PostgreSQL/MySQL, you typically must orchestrate it.
- **Histogram and NDV decay**: the optimizer tracks not just row count but value distribution (number of distinct values, histogram buckets). Bulk inserts can make a distribution unrecognizable; don't assume old histograms hold.
- **Adaptive query optimization** (Snowflake, SQL Server) mitigates this by learning during execution and re-optimizing mid-query, but don't rely on it as a substitute for statistics hygiene.
- **Connect to cardinality estimation**: staleness is fundamentally about the optimizer's cardinality model diverging from reality. Learn to read EXPLAIN PLAN output and spot inflated/deflated row estimates; that's your early warning sign.
