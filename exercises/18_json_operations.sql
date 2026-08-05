-- Practice: JSON & JSONB in PostgreSQL
-- Task 1: Access a JSON field with -> (returns JSON) and ->> (returns text)

-- Assume job_postings_fact has a jsonb column: job_details
SELECT
    job_id,
    job_details -> 'skills'            AS skills_json,
    job_details ->> 'company_name'     AS company_text
FROM job_postings_fact
LIMIT 10;

-- Task 2: Access nested keys

SELECT
    job_id,
    job_details -> 'location' ->> 'city' AS city
FROM job_postings_fact
LIMIT 10;

-- Task 3: Filter rows where a JSON key equals a value

SELECT job_id, job_details ->> 'company_name' AS company
FROM job_postings_fact
WHERE job_details ->> 'remote' = 'true';

-- Task 4: jsonb_array_elements — explode a JSON array into rows

SELECT
    job_id,
    jsonb_array_elements_text(job_details -> 'skills') AS skill
FROM job_postings_fact
WHERE job_details ? 'skills'
LIMIT 20;

-- Task 5: Aggregate — count jobs per skill from nested JSON array

SELECT
    skill,
    COUNT(*) AS job_count
FROM job_postings_fact,
     jsonb_array_elements_text(job_details -> 'skills') AS skill
GROUP BY skill
ORDER BY job_count DESC
LIMIT 15;

-- Task 6: Build JSON output with json_build_object

SELECT
    job_id,
    json_build_object(
        'title',  job_title_short,
        'salary', salary_year_avg,
        'remote', job_work_from_home
    ) AS job_summary
FROM job_postings_fact
LIMIT 5;

-- Task 7: jsonb_set — update a value inside a jsonb column

UPDATE job_postings_fact
SET job_details = jsonb_set(job_details, '{reviewed}', 'true'::jsonb)
WHERE job_id = 1;
