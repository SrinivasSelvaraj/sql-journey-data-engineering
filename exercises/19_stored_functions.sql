-- Practice: Stored Functions & Procedures in PostgreSQL
-- Task 1: Simple scalar function — classify salary into a band

CREATE OR REPLACE FUNCTION salary_band(salary NUMERIC)
RETURNS TEXT AS $$
BEGIN
    RETURN CASE
        WHEN salary >= 150000 THEN 'Senior'
        WHEN salary >= 100000 THEN 'Mid'
        WHEN salary >= 60000  THEN 'Junior'
        ELSE 'Entry'
    END;
END;
$$ LANGUAGE plpgsql;

-- Use it in a query
SELECT job_title_short, salary_year_avg, salary_band(salary_year_avg)
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
LIMIT 10;

-- Task 2: Function returning a table (set-returning function)

CREATE OR REPLACE FUNCTION top_paying_jobs(min_salary NUMERIC, row_limit INT)
RETURNS TABLE(job_title TEXT, salary NUMERIC, location TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT job_title_short::TEXT, salary_year_avg, job_location::TEXT
    FROM job_postings_fact
    WHERE salary_year_avg >= min_salary
    ORDER BY salary_year_avg DESC
    LIMIT row_limit;
END;
$$ LANGUAGE plpgsql;

SELECT * FROM top_paying_jobs(130000, 5);

-- Task 3: Function with OUT parameters

CREATE OR REPLACE FUNCTION salary_stats(
    OUT avg_sal NUMERIC,
    OUT max_sal NUMERIC,
    OUT min_sal NUMERIC
) AS $$
BEGIN
    SELECT AVG(salary_year_avg), MAX(salary_year_avg), MIN(salary_year_avg)
    INTO avg_sal, max_sal, min_sal
    FROM job_postings_fact
    WHERE salary_year_avg IS NOT NULL;
END;
$$ LANGUAGE plpgsql;

SELECT * FROM salary_stats();

-- Task 4: Stored procedure (no return value, use for DML)

CREATE OR REPLACE PROCEDURE archive_old_postings(cutoff_date DATE)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM job_postings_fact
    WHERE job_posted_date < cutoff_date;
    RAISE NOTICE 'Archived postings before %', cutoff_date;
END;
$$;

-- Call the procedure (use CALL, not SELECT)
-- CALL archive_old_postings('2024-01-01');

-- Task 5: Drop functions when done (cleanup)
-- DROP FUNCTION IF EXISTS salary_band(NUMERIC);
-- DROP FUNCTION IF EXISTS top_paying_jobs(NUMERIC, INT);
-- DROP FUNCTION IF EXISTS salary_stats();
-- DROP PROCEDURE IF EXISTS archive_old_postings(DATE);
