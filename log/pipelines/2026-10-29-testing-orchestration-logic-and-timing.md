---
date: 2026-10-29
phase: pipelines
topic: Testing orchestration logic and timing
---

# Testing orchestration logic and timing

*Pipelines and orchestration*

## Concept

Testing orchestration logic means validating that tasks run in the correct sequence, with proper dependency handling, and that timing constraints (SLAs, intervals, retries) behave as expected. This differs from testing individual job logic—you're checking that the *scheduler* does what you told it to do, not whether the SQL is correct.

When it matters: upstream delays cascade downstream; a job that should fail loudly instead silently produces stale data; a retry loop hammers your database; a backfill overwrites fresh results. Without orchestration tests, you ship workflows that work once in dev but crumble under real scheduling pressure, data volume, and failure modes.

What breaks: missing dependencies let tasks start too early, polluting fresh tables with incomplete inputs. Loose retry logic masks transient failures until the pipeline becomes unreliable. Timing assumptions (e.g., "data lands at midnight") break when they don't, and you have no circuit-breaker to stop the bleeding.

## Practice

**Problem:** A daily pipeline loads job postings, then immediately aggregates salary by location. But the upstream source sometimes arrives 2–4 hours late. The aggregation job fails silently, backfills yesterday's bucket, and overwrites today's partial results. Users see dropped salary records. You need to test that the aggregation job either waits for upstream data or fails visibly.

```sql
-- Test: aggregation job must not run until upstream table has rows for today
-- In your orchestration test (pseudo-code logic):

SELECT 
  job_location,
  COUNT(*) as job_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
GROUP BY job_location
HAVING COUNT(*) > 0
ORDER BY avg_salary DESC;

-- Orchestration assertion: 
-- - If upstream job_postings_fact for today is empty, BLOCK aggregation and alert.
-- - If aggregation runs anyway, it produces zero rows; downstream dashboards notice the gap.
-- - Retry logic: aggregation retries up to 5 times with exponential backoff (max 4 hours),
--   then fails the entire day's run, not just this task.
```

## Notes

- **Test the scheduler, not the transform:** Use a test-only dag with short intervals, injected delays, and failure injection to verify retry counts, timeout behavior, and dependency propagation.
- **Backfill and idempotency go hand-in-hand:** Test that re-running a job for the same date partition doesn't double-count or leave orphaned records; use `INSERT OVERWRITE` or unique constraints.
- **Alert on silence, not just failure:** A job that runs but produces zero rows is often worse than one that crashes; add data-quality checks (min row count, staleness thresholds) and fail the orchestration if they trip.
- **SLA and timing assumptions are documentation debts:** Write down "upstream lands by 06:00 UTC" and test it; when the assumption breaks, the test tells you before users do.
- **Adjacent: observability & monitoring** — orchestration tests are useless if you can't trace task execution, logs, and state; ensure your scheduler emits timestamps, duration, retry count, and failure reason to a queryable log.
