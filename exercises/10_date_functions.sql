-- Practice: Date & Time Functions
-- Task 1: Extract year, month, and day from job posted date

SELECT
    job_id,
    job_posted_date,
    EXTRACT(YEAR FROM job_posted_date)  AS post_year,
    EXTRACT(MONTH FROM job_posted_date) AS post_month,
    EXTRACT(DAY FROM job_posted_date)   AS post_day
FROM job_postings_fact
LIMIT 10;

-- Task 2: Count job postings per month to spot hiring trends

SELECT
    EXTRACT(YEAR FROM job_posted_date)  AS year,
    EXTRACT(MONTH FROM job_posted_date) AS month,
    COUNT(*) AS postings
FROM job_postings_fact
GROUP BY year, month
ORDER BY year, month;

-- Task 3: Truncate to month boundary (useful for time-series grouping)

SELECT
    DATE_TRUNC('month', job_posted_date) AS month_start,
    COUNT(*) AS postings
FROM job_postings_fact
GROUP BY month_start
ORDER BY month_start;

-- Task 4: Find jobs posted in the last 90 days relative to max date in data

SELECT
    job_id,
    job_title_short,
    job_posted_date
FROM job_postings_fact
WHERE job_posted_date >= (
    SELECT MAX(job_posted_date) - INTERVAL '90 days'
    FROM job_postings_fact
)
ORDER BY job_posted_date DESC
LIMIT 10;

-- Task 5: Days between posting date and end of year

SELECT
    job_id,
    job_posted_date,
    DATE_PART('doy', DATE '2023-12-31') - DATE_PART('doy', job_posted_date) AS days_remaining_in_year
FROM job_postings_fact
LIMIT 10;
