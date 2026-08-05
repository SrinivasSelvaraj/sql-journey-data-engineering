-- Practice: Advanced Aggregations (ROLLUP, CUBE, GROUPING SETS)
-- Task 1: Total salary stats per job title using standard aggregation

SELECT
    job_title_short,
    ROUND(AVG(salary_year_avg), 0) AS avg_salary,
    ROUND(MIN(salary_year_avg), 0) AS min_salary,
    ROUND(MAX(salary_year_avg), 0) AS max_salary,
    COUNT(*) AS posting_count
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY avg_salary DESC;

-- Task 2: ROLLUP — subtotals by job title, with a grand total row

SELECT
    job_title_short,
    ROUND(AVG(salary_year_avg), 0) AS avg_salary,
    COUNT(*) AS postings
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY ROLLUP(job_title_short)
ORDER BY job_title_short NULLS LAST;

-- Task 3: GROUPING SETS — salary stats by remote flag AND by job title (separate groups)

SELECT
    job_title_short,
    job_work_from_home,
    ROUND(AVG(salary_year_avg), 0) AS avg_salary,
    COUNT(*) AS postings
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY GROUPING SETS (
    (job_title_short),
    (job_work_from_home),
    ()
)
ORDER BY job_title_short NULLS LAST, job_work_from_home NULLS LAST;

-- Task 4: PERCENTILE — find median salary per job title

SELECT
    job_title_short,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg) AS p25_salary,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) AS p75_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
ORDER BY median_salary DESC NULLS LAST;

-- Task 5: FILTER clause — conditional aggregation without CASE WHEN

SELECT
    job_title_short,
    COUNT(*) AS total_jobs,
    COUNT(*) FILTER (WHERE job_work_from_home = TRUE)  AS remote_jobs,
    COUNT(*) FILTER (WHERE salary_year_avg >= 100000)  AS high_salary_jobs
FROM job_postings_fact
GROUP BY job_title_short
ORDER BY total_jobs DESC;
