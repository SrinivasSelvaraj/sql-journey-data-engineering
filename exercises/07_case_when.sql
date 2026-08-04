-- Practice: CASE WHEN
-- Task 1: Bucket salaries into bands

SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    CASE
        WHEN salary_year_avg >= 150000 THEN 'High'
        WHEN salary_year_avg >= 100000 THEN 'Mid'
        WHEN salary_year_avg IS NOT NULL THEN 'Low'
        ELSE 'Unknown'
    END AS salary_band
FROM job_postings_fact
ORDER BY salary_year_avg DESC NULLS LAST;

-- Task 2: Flag remote vs on-site jobs

SELECT
    job_id,
    job_title_short,
    CASE
        WHEN job_work_from_home = TRUE THEN 'Remote'
        ELSE 'On-site'
    END AS work_type
FROM job_postings_fact;

-- Task 3: Count of high/mid/low salary jobs per job title

SELECT
    job_title_short,
    COUNT(CASE WHEN salary_year_avg >= 150000 THEN 1 END) AS high_salary,
    COUNT(CASE WHEN salary_year_avg BETWEEN 100000 AND 149999 THEN 1 END) AS mid_salary,
    COUNT(CASE WHEN salary_year_avg < 100000 THEN 1 END) AS low_salary
FROM job_postings_fact
GROUP BY job_title_short
ORDER BY job_title_short;
