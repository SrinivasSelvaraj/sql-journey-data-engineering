-- Practice: Common Table Expressions (CTEs)
-- Task 1: Average salary per company, then filter companies above 120k avg

WITH company_avg_salary AS (
    SELECT
        company_id,
        AVG(salary_year_avg) AS avg_salary
    FROM job_postings_fact
    GROUP BY company_id
)
SELECT
    cd.name AS company_name,
    ROUND(cas.avg_salary, 0) AS avg_salary
FROM company_avg_salary AS cas
INNER JOIN company_dim AS cd ON cas.company_id = cd.company_id
WHERE cas.avg_salary > 120000
ORDER BY avg_salary DESC;

-- Task 2: Rank skills by demand and return only the top 10

WITH skill_demand AS (
    SELECT
        sd.skills,
        COUNT(*) AS job_count
    FROM skills_job_dim AS sjd
    INNER JOIN skills_dim AS sd ON sjd.skill_id = sd.skill_id
    GROUP BY sd.skills
)
SELECT skills, job_count
FROM skill_demand
ORDER BY job_count DESC
LIMIT 10;

-- Task 3: Jobs above their job_title_short salary average (chained CTEs)

WITH title_avg AS (
    SELECT job_title_short, AVG(salary_year_avg) AS avg_sal
    FROM job_postings_fact
    GROUP BY job_title_short
)
SELECT
    jpf.job_id,
    jpf.job_title_short,
    jpf.salary_year_avg,
    ROUND(ta.avg_sal, 0) AS title_avg_salary
FROM job_postings_fact AS jpf
INNER JOIN title_avg AS ta ON jpf.job_title_short = ta.job_title_short
WHERE jpf.salary_year_avg > ta.avg_sal
ORDER BY jpf.salary_year_avg DESC;
