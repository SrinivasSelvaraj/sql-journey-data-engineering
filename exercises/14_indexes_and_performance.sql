-- Practice: Indexes & Query Performance
-- Task 1: Check existing indexes on the fact table (PostgreSQL)

SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'job_postings_fact';

-- Task 2: EXPLAIN — read the query plan before adding indexes

EXPLAIN
SELECT *
FROM job_postings_fact
WHERE salary_year_avg > 120000;

-- Task 3: EXPLAIN ANALYZE — run the query and show actual vs estimated cost

EXPLAIN ANALYZE
SELECT
    j.job_title_short,
    AVG(j.salary_year_avg) AS avg_salary
FROM job_postings_fact j
WHERE j.job_work_from_home = TRUE
GROUP BY j.job_title_short;

-- Task 4: Create an index on a commonly filtered column

CREATE INDEX IF NOT EXISTS idx_salary ON job_postings_fact(salary_year_avg);
CREATE INDEX IF NOT EXISTS idx_remote  ON job_postings_fact(job_work_from_home);

-- Re-run EXPLAIN ANALYZE after the index and compare the cost
EXPLAIN ANALYZE
SELECT *
FROM job_postings_fact
WHERE salary_year_avg > 120000;

-- Task 5: Partial index — only index remote jobs (smaller, faster for filtered queries)

CREATE INDEX IF NOT EXISTS idx_remote_jobs
ON job_postings_fact(salary_year_avg)
WHERE job_work_from_home = TRUE;

-- Task 6: Drop indexes when done (cleanup)
-- DROP INDEX IF EXISTS idx_salary;
-- DROP INDEX IF EXISTS idx_remote;
-- DROP INDEX IF EXISTS idx_remote_jobs;
