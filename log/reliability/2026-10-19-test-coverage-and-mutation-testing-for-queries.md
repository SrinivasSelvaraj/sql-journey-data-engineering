---
date: 2026-10-19
phase: reliability
topic: Test coverage and mutation testing for queries
---

# Test coverage and mutation testing for queries

*Quality, reliability and the professional layer*

## Concept

Test coverage for data pipelines measures what fraction of your query logic is exercised by tests—but coverage alone is vanity. Mutation testing goes further: it deliberately breaks your queries (changing `>` to `>=`, removing `WHERE` clauses, altering `JOIN` conditions) and checks whether your tests catch the defect. If a mutated query passes all tests unchanged, your tests are blind to that logic.

This matters because a query can look correct and hit 100% code coverage while still silently corrupting data. A `WHERE salary > 0` that should exclude nulls won't fail a test that only checks row count. A `LEFT JOIN` used instead of `INNER JOIN` might produce duplicate revenue rows but pass a basic uniqueness check on a subset of columns.

Without mutation testing, you discover data bugs in production—not in code review. Teams that own pipelines use it to prevent the class of defects where "the query ran without error" masks logic errors. It's the difference between tests that look good and tests that actually catch mistakes.

## Practice

**Problem:** Write tests for a query that calculates average salary by job title for fully remote positions posted in 2024, excluding outliers above the 95th percentile per title.

```sql
-- The query being tested
WITH remote_2024 AS (
  SELECT job_title_short, salary_year_avg
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
    AND YEAR(job_posted_date) = 2024
    AND salary_year_avg IS NOT NULL
),
percentiles AS (
  SELECT 
    job_title_short,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY salary_year_avg) AS p95
  FROM remote_2024
  GROUP BY job_title_short
)
SELECT 
  r.job_title_short,
  COUNT(*) as job_count,
  ROUND(AVG(r.salary_year_avg), 2) as avg_salary_trimmed
FROM remote_2024 r
JOIN percentiles p ON r.job_title_short = p.job_title_short
WHERE r.salary_year_avg <= p.p95
GROUP BY r.job_title_short
HAVING COUNT(*) >= 5
ORDER BY avg_salary_trimmed DESC;

-- Mutation-aware test cases
-- Test 1: Catch mutation of = TRUE to IS NULL (lose remote filter)
SELECT ASSERT_EQUAL(
  (SELECT COUNT(DISTINCT job_work_from_home) 
   FROM (SELECT DISTINCT job_work_from_home FROM job_postings_fact 
         WHERE job_work_from_home = TRUE AND YEAR(job_posted_date) = 2024) t),
  1,
  'Query must filter to remote positions only'
);

-- Test 2: Catch mutation of <= p95 to < p95 (include boundary)
SELECT ASSERT_TRUE(
  (SELECT MAX(salary_year_avg) FROM <query_result>) 
  <= (SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY salary_year_avg) 
      FROM job_postings_fact WHERE job_work_from_home = TRUE AND YEAR(job_posted_date) = 2024),
  'No salary should exceed 95th percentile'
);

-- Test 3: Catch mutation of HAVING COUNT >= 5 (include tiny groups)
SELECT ASSERT_TRUE(
  (SELECT MIN(job_count) FROM <query_result>) >= 5,
  'All result groups must have at least 5 jobs'
);

-- Test 4: Catch mutation of IS NOT NULL (include nulls in avg)
SELECT ASSERT_FALSE(
  EXISTS(SELECT 1 FROM remote_2024 WHERE salary_year_avg IS NULL),
  'NULL salaries must be excluded from calculation'
);

-- Test 5: Catch JOIN type mutation (LEFT to INNER)
SELECT ASSERT_EQUAL(
  (SELECT COUNT(*) FROM <query_result>),
  (SELECT COUNT(DISTINCT job_title_short) FROM remote_2024 
   WHERE salary_year_avg IS NOT NULL AND PERCENTILE_CONT(0.95) WITHIN GROUP(ORDER BY salary_year_avg) OVER (PARTITION BY job_title_short) IS NOT NULL),
  'All titles with valid data should appear in result'
);
```

## Notes

- **Mistake:** Testing only happy paths. If your test data has no nulls, no outliers, or no title with <5 jobs, mutations in those branches hide forever.
- **Mistake:** Confusing row count with correctness. A test that checks `COUNT(*) > 0` passes whether you truncate a table or multiply rows via bad joins.
- **Adjacent topic:** Property-based testing—generative test frameworks that mutate data (not queries) to find brittle assumptions in your logic.
- **Adjacent topic:** Data contract testing—asserting schema, freshness, and cardinality upstream to catch bugs before they propagate.
- **Revisit:** Start mutation
