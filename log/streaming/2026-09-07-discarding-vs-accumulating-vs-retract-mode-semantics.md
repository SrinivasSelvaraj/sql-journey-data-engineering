---
date: 2026-09-07
phase: streaming
topic: Discarding vs accumulating vs retract mode semantics
---

# Discarding vs accumulating vs retract mode semantics

*Streaming and distributed processing*

## Concept

In streaming systems, the same logical record may arrive multiple times—due to retries, late data, or upstream reprocessing—and you must decide how to handle duplicates. **Discard mode** ignores all but the first arrival, **accumulate mode** keeps all versions (useful for append-only audit trails), and **retract mode** treats later arrivals as corrections: you emit the old row as a retraction (negative) and the new row as an insertion (positive).

Retract mode is essential when facts change mid-stream. Without it, you either lose corrections (discard) or bloat your state with conflicting versions (accumulate). Consider a job posting that gets salary updated or location corrected hours after posting: in discard mode, downstream consumers see stale data forever; in retract mode, you send "undo the old salary" + "insert corrected salary," and any aggregate (count, average) recalculates correctly.

The mode you choose affects state size, correctness of aggregations, and how you join streams. Retract mode requires a key to identify which row to retract; it's heavier but necessary for accurate real-time analytics when upstream changes are frequent.

## Practice

**Problem:** Job postings arrive with initial salary estimates, but corrections arrive later (same job_id, newer timestamp). You need to maintain an accurate count of postings by job_title_short and the average salary_year_avg per title, updating in real time.

```sql
-- Retract-mode solution: emit retractions for changed records
WITH incoming AS (
  SELECT 
    job_id, 
    job_title_short, 
    salary_year_avg, 
    job_posted_date,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY event_timestamp DESC) AS rn
  FROM job_postings_stream
),
latest_only AS (
  SELECT job_id, job_title_short, salary_year_avg, job_posted_date
  FROM incoming
  WHERE rn = 1
),
state_before AS (
  SELECT job_id, job_title_short, salary_year_avg
  FROM job_postings_state
),
changes AS (
  SELECT 
    COALESCE(s.job_id, l.job_id) AS job_id,
    s.job_title_short AS old_title,
    l.job_title_short AS new_title,
    s.salary_year_avg AS old_salary,
    l.salary_year_avg AS new_salary,
    CASE WHEN s.job_id IS NULL THEN 'insert'
         WHEN l.job_id IS NULL THEN 'delete'
         ELSE 'update' END AS change_type
  FROM state_before s FULL OUTER JOIN latest_only l ON s.job_id = l.job_id
)
-- Emit retractions (negative counts) for old state, then new state
SELECT 
  old_title AS job_title_short, 
  old_salary AS salary_year_avg,
  -1 AS delta_count,
  -old_salary AS delta_salary_sum
FROM changes WHERE change_type IN ('delete', 'update')
UNION ALL
SELECT 
  new_title, 
  new_salary,
  1 AS delta_count,
  new_salary AS delta_salary_sum
FROM changes WHERE change_type IN ('insert', 'update');
```

## Notes

- **Discard mode + late corrections = silently wrong results**: Aggregates become stale and users don't know. Only safe if you can guarantee no corrections arrive after the first event.
- **State explosion**: Accumulate mode scales poorly; every duplicate version consumes memory. Use only for true audit logs where you need every version's timestamp.
- **Retract mode requires unique keys**: You must be able to identify "the old row" to retract. Without a reliable primary key (job_id here), retractions target the wrong rows.
- **Adjacent concept—Changelog semantics**: Think of retract mode as publishing a changelog: `-old_row, +new_row` is the dual of `UPDATE` in a database. Connectors to data lakes (Iceberg, Delta) use this pattern.
- **Revisit—Watermarks and allowed lateness**: Retract mode works best with a configured grace period; after that window closes, late corrections are dropped or trigger errors rather than retractions.
