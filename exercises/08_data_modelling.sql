-- Practice: Data Modelling
-- Task 1: Explore the star schema — identify fact and dimension tables

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Task 2: List all columns and data types in the fact table

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'job_postings_fact'
ORDER BY ordinal_position;

-- Task 3: Join fact table with all dimension tables (star join)

SELECT
    j.job_id,
    j.job_title_short,
    j.salary_year_avg,
    c.name AS company_name,
    s.skills
FROM job_postings_fact j
LEFT JOIN company_dim c ON j.company_id = c.company_id
LEFT JOIN skills_job_dim sj ON j.job_id = sj.job_id
LEFT JOIN skills_dim s ON sj.skill_id = s.skill_id
LIMIT 20;

-- Task 4: Count how many job postings each company has (cardinality check)

SELECT
    c.name AS company_name,
    COUNT(j.job_id) AS total_postings
FROM company_dim c
LEFT JOIN job_postings_fact j ON c.company_id = j.company_id
GROUP BY c.name
ORDER BY total_postings DESC
LIMIT 15;

-- Task 5: Find jobs that require multiple skills (bridge table usage)

SELECT
    j.job_id,
    j.job_title_short,
    COUNT(sj.skill_id) AS skill_count
FROM job_postings_fact j
JOIN skills_job_dim sj ON j.job_id = sj.job_id
GROUP BY j.job_id, j.job_title_short
HAVING COUNT(sj.skill_id) >= 5
ORDER BY skill_count DESC
LIMIT 10;
