---
date: 2026-08-26
phase: sql
topic: Execution plan caching and parameter sniffing issues
---

# Execution plan caching and parameter sniffing issues

*SQL for analytics and engineering*

## Concept

Execution plan caching occurs when a database (SQL Server, PostgreSQL, etc.) compiles a query once and reuses that plan for subsequent executions with different parameter values. This is efficient—compilation is expensive—but creates a trap: the optimizer chooses a plan based on the *first* set of parameter values it sees, then locks in that plan even if later parameters would benefit from a completely different strategy. This is **parameter sniffing**.

Parameter sniffing becomes a performance crisis when the first execution uses atypical data distribution. For example, a query filtering by `job_location = 'Remote'` might compile with a plan optimized for Remote jobs (maybe 40% of rows), but if the cached plan is later used with `job_location = 'San Francisco'` (0.1% of rows), the optimizer will use a scan instead of a seek, causing massive slowdown. The plan is *correct* but catastrophically inefficient for the new parameters.

This matters in analytics and production systems because: (1) test data often isn't representative—you optimize for edge cases that never happen in production, or vice versa; (2) batch jobs run with varied filters; (3) parameter sniffing can cause intermittent, hard-to-debug performance cliffs. Solutions include plan guides, query hints, local variable assignment, or parameter padding.

## Practice

**Problem:** You have a stored procedure that filters `job_postings_fact` by location. The first execution uses `@location = 'Remote'` (very common, 35% of rows). A downstream job later calls it with `@location = 'Topeka, Nebraska'` (rare, 0.02% of rows), but performance degrades 100×. Show a solution that avoids parameter sniffing.

```sql
-- ❌ Vulnerable to parameter sniffing
CREATE PROCEDURE sp_jobs_by_location_bad @location NVARCHAR(50)
AS
BEGIN
    SELECT job_id, job_title_short, salary_year_avg
    FROM job_postings_fact
    WHERE job_location = @location
    ORDER BY salary_year_avg DESC;
END;

-- ✅ Solution 1: Local variable assignment (breaks sniffing)
CREATE PROCEDURE sp_jobs_by_location_good @location NVARCHAR(50)
AS
BEGIN
    DECLARE @local_location NVARCHAR(50) = @location;
    SELECT job_id, job_title_short, salary_year_avg
    FROM job_postings_fact
    WHERE job_location = @local_location
    ORDER BY salary_year_avg DESC;
END;

-- ✅ Solution 2: RECOMPILE hint (always recompile, higher CPU cost)
CREATE PROCEDURE sp_jobs_by_location_recompile @location NVARCHAR(50)
AS
BEGIN
    SELECT job_id, job_title_short, salary_year_avg
    FROM job_postings_fact
    WHERE job_location = @location
    ORDER BY salary_year_avg DESC
    OPTION (RECOMPILE);
END;

-- ✅ Solution 3: OPTIMIZE FOR hint (compile for a known common case)
CREATE PROCEDURE sp_jobs_by_location_optimize @location NVARCHAR(50)
AS
BEGIN
    SELECT job_id, job_title_short, salary_year_avg
    FROM job_postings_fact
    WHERE job_location = @location
    ORDER BY salary_year_avg DESC
    OPTION (OPTIMIZE FOR (@location = 'Remote'));
END;
```

## Notes

- **Local variable assignment** (Solution 1) is the pragmatic default: it defers optimization to runtime, losing some sniffing benefit but avoiding the worst-case plan lock. Use when you can't predict parameter distribution.
- **RECOMPILE** adds ~5–10ms per execution but guarantees the plan fits each call's parameters. Reserve this for high-selectivity variance or when statistics are stale.
- **Statistics are upstream**: Parameter sniffing exploits outdated or skewed column statistics. Running `UPDATE STATISTICS` on `job_location` after data skew happens is often the cheapest fix—do this before blaming the parameter.
- **Test with production-like data**: In your test harness, run the same query with 10 different `@location` values to spot plan instability before production. Use `SET STATISTICS IO ON` to see if scans suddenly appear.
- **Adjacent concepts**: Plan forcing (SQL Server), plan hints, index selectivity, and histogram skew. Parameter sniffing is a special case of "compiled plan != runtime reality."
