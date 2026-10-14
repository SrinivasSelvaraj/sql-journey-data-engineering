---
date: 2026-10-14
phase: cloud
topic: Snowflake compute scaling: warehouse sizing and auto-suspend
---

# Snowflake compute scaling: warehouse sizing and auto-suspend

*Cloud platforms and storage*

## Concept

Warehouse sizing determines how many compute credits your queries consume and how fast they execute. Snowflake charges per credit per second of compute; a 4-cluster warehouse costs 4× the credits of a 1-cluster warehouse but processes data 4× faster in parallel. The optimal size balances query latency (need speed) against cost (avoid oversizing for small workloads). Auto-suspend automatically shuts down idle warehouses after a configurable period (default 10 minutes), preventing runaway costs when developers forget to manually suspend. Without auto-suspend, a stopped development warehouse left running overnight can waste hundreds of credits; without right-sizing, a single slow query on an undersized warehouse might take 30 minutes when a larger warehouse would finish in 2 minutes but cost less overall due to fewer total credits burned.

## Practice

**Problem:** A nightly batch job aggregating job posting salaries by location runs every day at 2 AM, processing ~500K rows. It currently uses a MEDIUM warehouse (2 clusters) and takes 8 minutes. Finance wants to cut warehouse spend by 50%. How do you diagnose if you can downsize safely?

```sql
-- Step 1: Check query profile from QUERY_HISTORY to see actual parallelism used
SELECT 
    query_id,
    query_text,
    execution_time,
    credits_used,
    warehouse_size
FROM snowflake.account_usage.query_history
WHERE query_text ILIKE '%job_postings_fact%'
  AND DATE(start_time) = CURRENT_DATE - 1
ORDER BY start_time DESC
LIMIT 10;

-- Step 2: Run the aggregation on a SMALL warehouse (1 cluster) and measure
ALTER WAREHOUSE dev_wh SET WAREHOUSE_SIZE = 'SMALL';

SELECT 
    job_location,
    COUNT(*) as posting_count,
    AVG(salary_year_avg) as avg_salary,
    MAX(job_posted_date) as latest_posting
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 7
GROUP BY job_location
ORDER BY posting_count DESC;

-- Step 3: Set auto-suspend to 5 minutes and auto-resume on next query
ALTER WAREHOUSE dev_wh 
    SET AUTO_SUSPEND = 5 
    AUTO_RESUME = TRUE;
```

If the SMALL warehouse finishes in ~10 minutes (acceptable for nightly), you save 50% spend. The auto-suspend catches forgotten warehouse shutdowns.

## Notes

- **Oversizing kills ROI:** A LARGE warehouse (8 clusters) on a 100K-row query doesn't speed it up proportionally—you pay 8× credits for maybe 20% faster execution due to query overhead.
- **Query profile is your friend:** Always check `QUERY_HISTORY` and the visual explain plan; if a query uses only 1 cluster of parallelism, a larger warehouse won't help.
- **Auto-suspend ≠ auto-resume for cost control:** Auto-resume is convenience; auto-suspend is cost safety. Set aggressive auto-suspend times (2–5 min) on dev/test warehouses.
- **Warehouse pooling and resource monitors:** For multi-team environments, use resource monitors to cap total spend per warehouse or department; prevents one rogue query from draining monthly budget.
- **Adjacent topic:** Query optimization (better indexes, materialized views) often beats throwing more clusters at slow queries; always optimize before scaling up.
