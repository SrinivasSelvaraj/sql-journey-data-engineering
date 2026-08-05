-- Practice: Type Casting & Data Type Conversion
-- Task 1: Cast salary from numeric to text for display formatting

SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    '$' || ROUND(salary_year_avg, 0)::TEXT AS salary_display
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
LIMIT 10;

-- Task 2: Cast posted date to DATE (strip the time component)

SELECT
    job_id,
    job_posted_date,
    job_posted_date::DATE AS posted_date_only,
    job_posted_date::TEXT AS posted_as_text
FROM job_postings_fact
LIMIT 10;

-- Task 3: CAST vs :: syntax (both are standard)

SELECT
    job_id,
    CAST(salary_year_avg AS INTEGER)   AS salary_int,
    CAST(job_posted_date AS DATE)      AS posted_date,
    salary_year_avg::INTEGER           AS salary_int_alt
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
LIMIT 10;

-- Task 4: Handle implicit cast failures safely with NULLIF and COALESCE

SELECT
    job_id,
    salary_year_avg,
    COALESCE(salary_year_avg::TEXT, 'Not disclosed') AS salary_label
FROM job_postings_fact
LIMIT 10;

-- Task 5: Convert boolean to integer for arithmetic (TRUE = 1, FALSE = 0)

SELECT
    job_title_short,
    COUNT(*) AS total,
    SUM(job_work_from_home::INTEGER) AS remote_count,
    ROUND(AVG(job_work_from_home::INTEGER) * 100, 1) AS remote_pct
FROM job_postings_fact
GROUP BY job_title_short
ORDER BY remote_pct DESC;
