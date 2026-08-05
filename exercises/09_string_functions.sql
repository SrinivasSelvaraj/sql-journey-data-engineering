-- Practice: String Functions
-- Task 1: Extract domain from job location (substring after comma)

SELECT
    job_id,
    job_location,
    TRIM(SPLIT_PART(job_location, ',', 2)) AS country_or_state
FROM job_postings_fact
WHERE job_location LIKE '%,%'
LIMIT 10;

-- Task 2: Standardise job titles to uppercase

SELECT
    job_id,
    job_title,
    UPPER(job_title) AS job_title_upper,
    LOWER(job_title) AS job_title_lower
FROM job_postings_fact
LIMIT 10;

-- Task 3: Find jobs where title contains 'data' (case-insensitive)

SELECT
    job_id,
    job_title,
    job_title_short
FROM job_postings_fact
WHERE LOWER(job_title) LIKE '%data%'
LIMIT 15;

-- Task 4: Concatenate company name and job title into a display label

SELECT
    j.job_id,
    c.name || ' — ' || j.job_title_short AS job_label
FROM job_postings_fact j
JOIN company_dim c ON j.company_id = c.company_id
LIMIT 10;

-- Task 5: Count character length of job titles and find the longest

SELECT
    job_title,
    LENGTH(job_title) AS title_length
FROM job_postings_fact
ORDER BY title_length DESC
LIMIT 10;
