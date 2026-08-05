-- Practice: Recursive CTEs
-- Task 1: Generate a number series with WITH RECURSIVE

WITH RECURSIVE number_series AS (
    SELECT 1 AS n              -- anchor: starting value
    UNION ALL
    SELECT n + 1               -- recursive: next value
    FROM number_series
    WHERE n < 10               -- termination condition
)
SELECT n FROM number_series;

-- Task 2: Generate a date series (useful for filling gaps in time-series data)

WITH RECURSIVE date_series AS (
    SELECT '2026-01-01'::DATE AS dt
    UNION ALL
    SELECT dt + INTERVAL '1 day'
    FROM date_series
    WHERE dt < '2026-01-31'::DATE
)
SELECT dt FROM date_series;

-- Task 3: Walk an org hierarchy (manager → report chain)
-- Assumes a table: employees(employee_id, name, manager_id)

WITH RECURSIVE org_tree AS (
    -- anchor: top-level employees (no manager)
    SELECT employee_id, name, manager_id, 1 AS depth
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- recursive: employees who report to someone already in the tree
    SELECT e.employee_id, e.name, e.manager_id, ot.depth + 1
    FROM employees e
    JOIN org_tree ot ON e.manager_id = ot.employee_id
)
SELECT depth, name FROM org_tree ORDER BY depth, name;

-- Task 4: Fill missing months in job posting data

WITH RECURSIVE months AS (
    SELECT DATE_TRUNC('month', MIN(job_posted_date))::DATE AS month_start
    FROM job_postings_fact
    UNION ALL
    SELECT (month_start + INTERVAL '1 month')::DATE
    FROM months
    WHERE month_start < DATE_TRUNC('month', NOW())
),
monthly_counts AS (
    SELECT DATE_TRUNC('month', job_posted_date)::DATE AS month_start,
           COUNT(*) AS postings
    FROM job_postings_fact
    GROUP BY 1
)
SELECT m.month_start, COALESCE(mc.postings, 0) AS postings
FROM months m
LEFT JOIN monthly_counts mc USING (month_start)
ORDER BY m.month_start;
