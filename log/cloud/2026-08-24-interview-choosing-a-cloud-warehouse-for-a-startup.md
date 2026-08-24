---
date: 2026-08-24
phase: cloud
topic: Interview: choosing a cloud warehouse for a startup
---

# Interview: choosing a cloud warehouse for a startup

*Cloud platforms and storage*

## Concept

Choosing a cloud warehouse for a startup requires balancing cost, performance, and operational simplicity. The three major options—Snowflake, BigQuery, and Redshift—differ fundamentally in pricing models (per-compute, per-query, or per-hour), scaling behavior, and maintenance overhead. Snowflake charges for storage and compute separately with automatic scaling; BigQuery bills per terabyte scanned; Redshift requires manual cluster management but offers predictable costs. What breaks without clarity: you'll either overspend on unused resources, get hit with surprise query costs, or face slow queries when your cluster undersizes. Understanding your startup's actual usage pattern—query frequency, data volume growth, concurrent users—directly determines which warehouse minimizes waste.

The interview angle focuses on demonstrating that you've thought beyond "which tool is fastest." Interviewers want to know you've considered operational costs, query optimization practices specific to each platform, and how you'd monitor spend. For a startup with unpredictable usage, BigQuery's per-query billing reduces idle cluster costs; for predictable analytical workloads, Redshift's fixed capacity is safer. Snowflake sits in the middle with flexibility but complexity.

## Practice

**Problem:** Your startup is running hourly analytical queries on a job postings dataset. You notice the same query analyzing remote work salary trends takes 45 seconds on your current warehouse and costs $0.45 per run (20 GB scanned). Your manager asks if you should switch platforms. Write the query and identify what's driving the cost.

```sql
SELECT 
  job_work_from_home,
  job_location,
  ROUND(AVG(salary_year_avg), 2) as avg_salary,
  COUNT(*) as job_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_work_from_home, job_location
ORDER BY avg_salary DESC;
```

**Cost drivers:** The query scans the entire `job_postings_fact` table (20 GB) because BigQuery lacks a clustered index on `job_posted_date`. Solution: cluster the table by `job_posted_date` and `job_work_from_home`. This reduces scanned data to ~2 GB, dropping cost to $0.045/run. Before switching platforms, optimize queries—the platform matters less than how you structure data and write queries.

## Notes

- **Pricing trap:** Don't compare warehouses on list price alone; a "cheaper" per-GB rate means nothing if you're scanning 10× more data due to poor partitioning or full table scans.
- **Query cost visibility:** Set up cost monitoring from day one. BigQuery's `INFORMATION_SCHEMA.JOBS_BY_PROJECT` and Snowflake's `QUERY_HISTORY` are non-negotiable for understanding spend patterns and bottlenecks.
- **Startup reality:** Early-stage startups often benefit from BigQuery or Athena because you pay only for what you query—zero waste on idle clusters—but switch to Redshift or Snowflake once usage becomes predictable and volume justifies reserved capacity.
- **Connects to:** data modeling (partitioning and clustering strategy), query optimization (predicate pushdown, materialized views), and observability (cost allocation by team or product feature).
- **Revisit when:** your data volume crosses 1 TB, you hit concurrent query limits, or you notice >20% of your cloud spend is database-related—these are signals to re-evaluate your platform choice.
