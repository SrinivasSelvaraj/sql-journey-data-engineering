-- Practice: Subqueries
-- Task 1: Jobs paying above the overall average salary

SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE salary_year_avg > (
    SELECT AVG(salary_year_avg)
    FROM job_postings_fact
)
ORDER BY salary_year_avg DESC;

-- Task 2: Companies that have posted at least one remote job

SELECT DISTINCT name
FROM company_dim
WHERE company_id IN (
    SELECT company_id
    FROM job_postings_fact
    WHERE job_work_from_home = TRUE
);

-- Task 3: Top 5 skills by number of job postings (subquery in FROM)

SELECT skills, posting_count
FROM (
    SELECT
        sd.skills,
        COUNT(*) AS posting_count
    FROM skills_job_dim AS sjd
    INNER JOIN skills_dim AS sd ON sjd.skill_id = sd.skill_id
    GROUP BY sd.skills
) AS skill_counts
ORDER BY posting_count DESC
LIMIT 5;
