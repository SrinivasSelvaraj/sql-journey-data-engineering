-- Practice: Window Functions
-- Task 1: Rank jobs by salary within each job title

SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    RANK() OVER (PARTITION BY job_title_short ORDER BY salary_year_avg DESC) AS salary_rank
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL;

-- Task 2: Running total of job postings by month

SELECT
    DATE_TRUNC('month', job_posted_date) AS month,
    COUNT(*) AS monthly_postings,
    SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', job_posted_date)) AS running_total
FROM job_postings_fact
GROUP BY DATE_TRUNC('month', job_posted_date)
ORDER BY month;

-- Task 3: Salary compared to previous and next posting within same job title

SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    LAG(salary_year_avg)  OVER (PARTITION BY job_title_short ORDER BY salary_year_avg) AS prev_salary,
    LEAD(salary_year_avg) OVER (PARTITION BY job_title_short ORDER BY salary_year_avg) AS next_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL;
