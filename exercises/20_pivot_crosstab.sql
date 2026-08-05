-- Practice: Pivoting Data in PostgreSQL
-- Task 1: Manual pivot with conditional aggregation (no extension needed)

SELECT
    job_title_short,
    ROUND(AVG(CASE WHEN EXTRACT(MONTH FROM job_posted_date) = 1  THEN salary_year_avg END), 0) AS jan,
    ROUND(AVG(CASE WHEN EXTRACT(MONTH FROM job_posted_date) = 2  THEN salary_year_avg END), 0) AS feb,
    ROUND(AVG(CASE WHEN EXTRACT(MONTH FROM job_posted_date) = 3  THEN salary_year_avg END), 0) AS mar,
    ROUND(AVG(CASE WHEN EXTRACT(MONTH FROM job_posted_date) = 4  THEN salary_year_avg END), 0) AS apr,
    ROUND(AVG(CASE WHEN EXTRACT(MONTH FROM job_posted_date) = 5  THEN salary_year_avg END), 0) AS may,
    ROUND(AVG(CASE WHEN EXTRACT(MONTH FROM job_posted_date) = 6  THEN salary_year_avg END), 0) AS jun
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
  AND EXTRACT(YEAR FROM job_posted_date) = 2023
GROUP BY job_title_short
ORDER BY job_title_short;

-- Task 2: Pivot boolean flag — count remote vs on-site per role

SELECT
    job_title_short,
    COUNT(*) FILTER (WHERE job_work_from_home = TRUE)  AS remote_count,
    COUNT(*) FILTER (WHERE job_work_from_home = FALSE) AS onsite_count,
    COUNT(*) AS total
FROM job_postings_fact
GROUP BY job_title_short
ORDER BY total DESC;

-- Task 3: Unpivot — turn columns back into rows using UNION ALL

SELECT 'remote'  AS work_type, COUNT(*) AS job_count FROM job_postings_fact WHERE job_work_from_home = TRUE
UNION ALL
SELECT 'onsite'  AS work_type, COUNT(*) AS job_count FROM job_postings_fact WHERE job_work_from_home = FALSE;

-- Task 4: Crosstab using tablefunc extension (requires: CREATE EXTENSION tablefunc)
-- This is the native PostgreSQL pivot function

-- CREATE EXTENSION IF NOT EXISTS tablefunc;
--
-- SELECT *
-- FROM crosstab(
--     $$
--     SELECT job_title_short,
--            EXTRACT(QUARTER FROM job_posted_date)::TEXT AS quarter,
--            ROUND(AVG(salary_year_avg), 0)::NUMERIC AS avg_salary
--     FROM job_postings_fact
--     WHERE salary_year_avg IS NOT NULL
--     GROUP BY 1, 2
--     ORDER BY 1, 2
--     $$,
--     $$ SELECT DISTINCT EXTRACT(QUARTER FROM job_posted_date)::TEXT
--        FROM job_postings_fact ORDER BY 1 $$
-- ) AS ct(role TEXT, q1 NUMERIC, q2 NUMERIC, q3 NUMERIC, q4 NUMERIC);
