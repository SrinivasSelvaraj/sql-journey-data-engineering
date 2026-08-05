-- Practice: Set Operations
-- Task 1: UNION — combine results from two queries (removes duplicates)

SELECT job_title_short, job_location
FROM job_postings_fact
WHERE job_location = 'New York, NY'

UNION

SELECT job_title_short, job_location
FROM job_postings_fact
WHERE job_location = 'San Francisco, CA';

-- Task 2: UNION ALL — combine results keeping duplicates (faster)

SELECT job_title_short FROM job_postings_fact WHERE salary_year_avg > 150000
UNION ALL
SELECT job_title_short FROM job_postings_fact WHERE job_work_from_home = TRUE;

-- Task 3: INTERSECT — rows that appear in BOTH result sets

SELECT job_title_short
FROM job_postings_fact
WHERE salary_year_avg > 120000

INTERSECT

SELECT job_title_short
FROM job_postings_fact
WHERE job_work_from_home = TRUE;

-- Task 4: EXCEPT — rows in the first set but NOT in the second

SELECT job_title_short
FROM job_postings_fact
WHERE salary_year_avg > 100000

EXCEPT

SELECT job_title_short
FROM job_postings_fact
WHERE job_work_from_home = TRUE;

-- Task 5: Combine with CTEs for readable multi-set logic

WITH high_pay AS (
    SELECT job_id, job_title_short
    FROM job_postings_fact
    WHERE salary_year_avg > 150000
),
remote AS (
    SELECT job_id, job_title_short
    FROM job_postings_fact
    WHERE job_work_from_home = TRUE
)
SELECT job_title_short FROM high_pay
INTERSECT
SELECT job_title_short FROM remote;

-- Task 6: UNION to build a report mixing fact rows and summary rows

SELECT job_title_short, salary_year_avg, 'detail' AS row_type
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
UNION ALL
SELECT 'ALL ROLES', AVG(salary_year_avg), 'summary'
FROM job_postings_fact;
