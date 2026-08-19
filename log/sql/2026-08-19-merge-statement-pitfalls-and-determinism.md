---
date: 2026-08-19
phase: sql
topic: MERGE statement pitfalls and determinism
---

# MERGE statement pitfalls and determinism

*SQL for analytics and engineering*

## Concept

A MERGE statement combines INSERT, UPDATE, and DELETE operations in a single atomic transaction, matching source rows against target rows using a join condition. However, MERGE becomes non-deterministic when the join condition matches a single source row to multiple target rows, or vice versa—the database must then decide which matched pair to process, leading to unpredictable results. This matters critically in analytics pipelines where you're upserting dimension tables or slowly changing dimensions (SCD Type 2); a non-deterministic MERGE can silently corrupt your fact tables by updating the wrong record or creating duplicate keys.

The root cause is ambiguous cardinality: if your ON clause doesn't guarantee 1:1 or 1:many (source-to-target) relationships, the optimizer may process matches in arbitrary order. Standard SQL doesn't formally require deterministic behavior in this scenario, and different databases (Snowflake, BigQuery, Postgres, T-SQL) handle it differently. Without explicit uniqueness constraints or careful filtering, a MERGE that works in development can produce silent failures in production as data volume or distribution changes.

Prevention requires: (1) enforcing unique constraints on the join key in both source and target, (2) explicitly filtering source/target to eliminate duplicates before MERGE, (3) testing cardinality assumptions in your WHERE and ON clauses, and (4) preferring explicit INSERT + UPDATE + DELETE steps when stakes are high, especially if you cannot guarantee 1:1 matching.

## Practice

**Problem:** You receive a daily feed of job postings and want to upsert them into `job_postings_fact` using job_id as the key. The feed occasionally contains duplicate job_ids from different crawl sources on the same day. A naive MERGE might update the wrong row or skip updates unpredictably. Write a deterministic merge that handles duplicates safely.

```sql
-- WRONG: Non-deterministic if job_postings_fact has duplicates or feed has duplicates
MERGE INTO job_postings_fact t
USING raw_job_feed s
ON t.job_id = s.job_id
WHEN MATCHED THEN UPDATE SET t.salary_year_avg = s.salary_year_avg
WHEN NOT MATCHED THEN INSERT (job_id, job_title_short, salary_year_avg, job_location)
  VALUES (s.job_id, s.job_title_short, s.salary_year_avg, s.job_location);

-- CORRECT: Deduplicate source, enforce target uniqueness, explicit cardinality checks
WITH deduped_feed AS (
  SELECT 
    job_id, 
    job_title_short, 
    salary_year_avg, 
    job_location,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC, salary_year_avg DESC) AS rn
  FROM raw_job_feed
  WHERE job_posted_date = CURRENT_DATE
)
MERGE INTO job_postings_fact t
USING deduped_feed s
ON t.job_id = s.job_id AND s.rn = 1  -- Explicit determinism: take latest/highest salary per job_id
WHEN MATCHED THEN 
  UPDATE SET 
    t.job_title_short = s.job_title_short,
    t.salary_year_avg = COALESCE(s.salary_year_avg, t.salary_year_avg),
    t.job_location = s.job_location
WHEN NOT MATCHED THEN 
  INSERT (job_id, job_title_short, salary_year_avg, job_location)
  VALUES (s.job_id, s.job_title_short, s.salary_year_avg, s.job_location);
```

## Notes

- **Duplicate key antipattern:** Always check if your source or target has duplicates on the join key before writing MERGE; use `GROUP BY` + `COUNT(*) > 1` or window functions to surface them.
- **Cardinality is implicit:** MERGE doesn't fail on many-to-many matches; it silently processes them. Add explicit `ROW_NUMBER()` or `RANK()` to enforce your intended cardinality assumption.
- **Test with small samples:** Run MERGE logic on a subset of rows and compare result row counts to source/target counts to validate 1:1 matching before full deployment.
- **Atomic transactions matter:** MERGE is atomic (all-or-nothing), which is good for consistency, but non-determinism corrupts the entire transaction; determinism is a prerequisite for correctness, not a side benefit.
- **Related: SCD Type 2, upsert patterns, idempotency:** This ties to slowly changing dimensions, INSERT OR REPLACE anti-patterns, and designing pipelines that tolerate re-runs without duplication.
