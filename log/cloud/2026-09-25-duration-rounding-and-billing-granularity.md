---
date: 2026-09-25
phase: cloud
topic: Duration rounding and billing granularity
---

# Duration rounding and billing granularity

*Cloud platforms and storage*

## Concept

Duration rounding and billing granularity determine how cloud platforms charge you for compute and storage resources—and why query performance can degrade unexpectedly. Most platforms (BigQuery, Redshift, Athena, Snowflake) round query execution time up to the nearest billing increment (typically 1 second, 1 minute, or 1 slot-second). A 1.2-second query costs the same as a 2-second query if the increment is 1 second; running 100 sub-second queries may be cheaper than running one 61-second query if your platform bills per minute. Understanding these thresholds prevents bill shock and reveals why batching or partitioning strategies matter more than raw query time.

Billing granularity also affects storage: some platforms charge for monthly snapshots or daily minimums, meaning deleting 10 GB of data mid-month may not reduce your bill. Query slot reservations introduce their own rounding—a 500-slot job running for 1.1 minutes consumes 500 slot-minutes (rounded up), not 550 slot-seconds. Without awareness of these rules, you might optimize query logic while ignoring the more expensive lever: reducing query count or batch size.

## Practice

**Problem:** You're analyzing job postings and running daily queries to calculate average salary by job title and location. Currently, you run 50 separate queries per day (one per job title + location combination), each taking 0.8 seconds. You're billed per second (rounded up), so each query costs 1 second's worth. Redesign to batch the logic into fewer, longer queries and calculate the billing impact.

```sql
-- Instead of 50 separate queries like:
-- SELECT AVG(salary_year_avg) FROM job_postings_fact WHERE job_title_short = 'Data Analyst' AND job_location = 'New York';
-- ... × 50 (50 seconds billed)

-- Write one batched query:
SELECT
  job_title_short,
  job_location,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  MIN(job_posted_date) as earliest_post
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 1
GROUP BY job_title_short, job_location
ORDER BY job_title_short, job_location;

-- This single query runs ~4 seconds, billed as 4 seconds (vs. 50 seconds for individual queries)
-- Added benefit: single result set, simpler orchestration, less API overhead
```

## Notes

- **Slot vs. time billing:** Redshift and BigQuery offer slot reservations (flat monthly cost for guaranteed capacity). A 1-second query on slots costs the same as a 60-second query if both fit in your slot commitment—incentivizing larger, fewer queries over many small ones.
- **Storage minimums and snapshots:** Snowflake bills on average daily storage, BigQuery on daily snapshots. Deleting data mid-month may not save money until the next month; batch deletes for predictability.
- **Partition pruning + granularity:** Rounding loses its bite when queries scan unnecessary partitions. Ensure WHERE clauses hit partition keys (e.g., `job_posted_date`) so you reduce *bytes scanned*, not just query count.
- **Adjacent concepts:** Query caching, materialized views, and result set reuse are closely tied—they reduce query count before you even hit rounding thresholds. Always profile cost per query before optimizing logic.
- **Revisit after:** Cost attribution (how to tag queries by team/project), incremental load patterns (append-only tables minimize re-scanning), and query result lifecycle (when to archive or delete old results).
