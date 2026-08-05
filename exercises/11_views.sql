-- Practice: Views
-- Task 1: Create a view for high-paying remote jobs

CREATE OR REPLACE VIEW high_paying_remote AS
SELECT
    j.job_id,
    j.job_title_short,
    j.salary_year_avg,
    j.job_work_from_home,
    c.name AS company_name
FROM job_postings_fact j
JOIN company_dim c ON j.company_id = c.company_id
WHERE j.job_work_from_home = TRUE
  AND j.salary_year_avg >= 100000;

-- Query the view
SELECT * FROM high_paying_remote
ORDER BY salary_year_avg DESC
LIMIT 10;

-- Task 2: Create a view that aggregates skills demand

CREATE OR REPLACE VIEW skills_demand AS
SELECT
    s.skills,
    s.type AS skill_type,
    COUNT(sj.job_id) AS job_count
FROM skills_dim s
JOIN skills_job_dim sj ON s.skill_id = sj.skill_id
GROUP BY s.skills, s.type;

-- Query the view — top 10 most in-demand skills
SELECT * FROM skills_demand
ORDER BY job_count DESC
LIMIT 10;

-- Task 3: Create a view joining all tables for a flat reporting layer

CREATE OR REPLACE VIEW job_full_detail AS
SELECT
    j.job_id,
    j.job_title_short,
    j.job_location,
    j.job_posted_date,
    j.salary_year_avg,
    j.job_work_from_home,
    c.name AS company_name,
    s.skills,
    s.type AS skill_category
FROM job_postings_fact j
LEFT JOIN company_dim c ON j.company_id = c.company_id
LEFT JOIN skills_job_dim sj ON j.job_id = sj.job_id
LEFT JOIN skills_dim s ON sj.skill_id = s.skill_id;

-- Sample from the flat view
SELECT * FROM job_full_detail LIMIT 5;

-- Task 4: Drop views when done (cleanup)
-- DROP VIEW IF EXISTS high_paying_remote;
-- DROP VIEW IF EXISTS skills_demand;
-- DROP VIEW IF EXISTS job_full_detail;
