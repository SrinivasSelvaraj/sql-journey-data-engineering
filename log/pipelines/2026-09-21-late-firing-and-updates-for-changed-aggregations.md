---
date: 2026-09-21
phase: pipelines
topic: Late firing and updates for changed aggregations
---

# Late firing and updates for changed aggregations

*Pipelines and orchestration*

## Concept

Late firing and updates for changed aggregations address the problem of stale or incorrect aggregate results when source data changes after initial computation. This occurs because aggregations (sums, counts, averages) are typically materialized once and not recalculated when underlying facts are inserted, updated, or deleted. Without late firing, a user querying "total jobs posted last month" may see yesterday's number even though five new postings arrived this morning. Late firing mechanisms—whether time-based triggers, change-data-capture (CDC) listeners, or scheduled reruns—detect these changes and regenerate affected aggregations. Updates for changed aggregations ensure that dependent downstream models (reports, dashboards, ML features) receive fresh data rather than stale cached values, which is especially critical in analytical systems where business decisions depend on recent facts.

The stakes are highest in fast-moving domains: job boards, pricing engines, fraud detection. A hiring manager reviewing job_postings aggregates needs to see the latest salary trends *now*, not next Tuesday. Without late firing, you face a choice: either accept data latency or abandon aggregations altogether and compute on-the-fly (slow). The right approach is explicit, observable late-firing logic that fails loudly when it can't keep up.

## Practice

**Problem:** You maintain a daily aggregate table `job_postings_agg` that counts and averages salaries by job title. New postings arrive throughout the day via an API. Your users expect the 9 AM dashboard to include postings from the last 24 hours, but your current daily batch job runs only at midnight, missing everything posted between midnight and 9 AM.

**Solution:** Implement a late-firing trigger using a scheduled check that detects when source data has changed and reruns the affected aggregate partition.

```sql
-- 1. Create the aggregate table with a load_ts tracking column
CREATE TABLE job_postings_agg AS
SELECT 
    job_title_short,
    COUNT(*) AS job_count,
    ROUND(AVG(salary_year_avg), 2) AS avg_salary,
    DATE(job_posted_date) AS posted_date,
    CURRENT_TIMESTAMP AS agg_load_ts
FROM job_postings_fact
GROUP BY job_title_short, DATE(job_posted_date);

-- 2. Create a watermark table to track the last successful aggregate refresh
CREATE TABLE agg_refresh_log (
    agg_name VARCHAR,
    partition_date DATE,
    last_refresh_ts TIMESTAMP,
    max_source_ts TIMESTAMP,
    PRIMARY KEY (agg_name, partition_date)
);

-- 3. Late-firing check: detect if new data arrived since last refresh
SELECT 
    MAX(job_posted_date) as max_source_date,
    MAX(CURRENT_TIMESTAMP) as check_time
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 1 DAY
HAVING MAX(job_posted_date) > 
    (SELECT COALESCE(MAX(last_refresh_ts), '1900-01-01'::TIMESTAMP)
     FROM agg_refresh_log 
     WHERE agg_name = 'job_postings_agg'
       AND partition_date = CURRENT_DATE - INTERVAL 1 DAY);

-- 4. If check returns rows, rerun the aggregate for that partition
DELETE FROM job_postings_agg 
WHERE posted_date = CURRENT_DATE - INTERVAL 1 DAY;

INSERT INTO job_postings_agg
SELECT 
    job_title_short,
    COUNT(*) AS job_count,
    ROUND(AVG(salary_year_avg), 2) AS avg_salary,
    DATE(job_posted_date) AS posted_date,
    CURRENT_TIMESTAMP AS agg_load_ts
FROM job_postings_fact
WHERE DATE(job_posted_date) = CURRENT_DATE - INTERVAL 1 DAY
GROUP BY job_title_short, DATE(job_posted_date);

-- 5. Update the refresh log
INSERT INTO agg_refresh_log (agg_name, partition_date, last_refresh_ts, max_source_ts)
SELECT 
    'job_postings_agg',
    CURRENT_DATE - INTERVAL 1 DAY,
    CURRENT_TIMESTAMP,
    MAX(job_posted_date)
FROM job_postings_fact
WHERE DATE(job_posted_date) = CURRENT_DATE - INTERVAL 1 DAY
ON CONFLICT (agg_name, partition_date) 
DO UPDATE SET last_refresh_ts = EXCLUDED.last_refresh_ts, max_source_ts = EXCLUDED.max_source_ts;
```

## Notes

- **Fail loudly:** If the late-firing check detects changes but the rerun fails, raise an alert immediately (via Airflow, dbt tests, or custom queries), not a silent skip. Stale aggregates are worse than missing ones.

- **Partition by time:** Always organize aggregates by date or hour so reruns touch only affected partitions, not the entire table. This
