SELECT
	job_title_short,
	AVG(salary_year_avg) AS avg_salary,
	MEDIAN(salary_year_avg) AS median_salary,
	MAX(salary_year_avg) AS max_salary
FROM job_postings_fact
GROUP BY job_title_short
HAVING MEDIAN(salary_year_avg) > 100000
ORDER BY avg_salary DESC;