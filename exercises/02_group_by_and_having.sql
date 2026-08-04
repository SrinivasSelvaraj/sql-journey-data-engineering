-- Practice: group by and having
-- Task: write a query that returns job_title_short and average salary for roles with a median salary above 90,000

SELECT
    job_title_short,
    AVG(salary_year_avg) AS avg_salary,
    MEDIAN(salary_year_avg) AS median_salary
FROM job_postings_fact
GROUP BY job_title_short
HAVING MEDIAN(salary_year_avg) > 90000
ORDER BY median_salary DESC;