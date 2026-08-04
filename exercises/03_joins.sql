-- Practice: JOINs
-- Task 1: INNER JOIN — job postings with company name

SELECT
    jpf.job_id,
    jpf.job_title_short,
    cd.name AS company_name
FROM job_postings_fact AS jpf
INNER JOIN company_dim AS cd ON jpf.company_id = cd.company_id;

-- Task 2: LEFT JOIN — all jobs with their skills (include jobs with no skills listed)

SELECT
    jpf.job_id,
    jpf.job_title_short,
    sd.skills
FROM job_postings_fact AS jpf
LEFT JOIN skills_job_dim AS sjd ON jpf.job_id = sjd.job_id
LEFT JOIN skills_dim AS sd ON sjd.skill_id = sd.skill_id;

-- Task 3: Companies with more than 10 Data Engineer postings

SELECT
    cd.name AS company_name,
    COUNT(*) AS posting_count
FROM job_postings_fact AS jpf
INNER JOIN company_dim AS cd ON jpf.company_id = cd.company_id
WHERE jpf.job_title_short = 'Data Engineer'
GROUP BY cd.name
HAVING COUNT(*) > 10
ORDER BY posting_count DESC;
