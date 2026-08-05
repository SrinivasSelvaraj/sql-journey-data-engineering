-- Practice: Table Partitioning in PostgreSQL
-- Task 1: Create a range-partitioned table (partition by date)

CREATE TABLE job_postings_partitioned (
    job_id          BIGINT,
    job_title_short TEXT,
    salary_year_avg NUMERIC,
    job_posted_date DATE NOT NULL
) PARTITION BY RANGE (job_posted_date);

-- Task 2: Create child partitions — one per quarter

CREATE TABLE job_postings_2023_q1
    PARTITION OF job_postings_partitioned
    FOR VALUES FROM ('2023-01-01') TO ('2023-04-01');

CREATE TABLE job_postings_2023_q2
    PARTITION OF job_postings_partitioned
    FOR VALUES FROM ('2023-04-01') TO ('2023-07-01');

CREATE TABLE job_postings_2023_q3
    PARTITION OF job_postings_partitioned
    FOR VALUES FROM ('2023-07-01') TO ('2023-10-01');

CREATE TABLE job_postings_2023_q4
    PARTITION OF job_postings_partitioned
    FOR VALUES FROM ('2023-10-01') TO ('2024-01-01');

-- Task 3: List partition — partition by a discrete column value

CREATE TABLE job_postings_by_type (
    job_id          BIGINT,
    job_title_short TEXT,
    salary_year_avg NUMERIC,
    work_type       TEXT NOT NULL
) PARTITION BY LIST (work_type);

CREATE TABLE job_postings_remote
    PARTITION OF job_postings_by_type
    FOR VALUES IN ('remote');

CREATE TABLE job_postings_onsite
    PARTITION OF job_postings_by_type
    FOR VALUES IN ('onsite', 'hybrid');

-- Task 4: Query the partitioned table — PostgreSQL routes to the right partition automatically
-- EXPLAIN shows which partition is scanned (partition pruning)

EXPLAIN
SELECT *
FROM job_postings_partitioned
WHERE job_posted_date BETWEEN '2023-01-01' AND '2023-03-31';

-- Task 5: Check which partitions exist for a table

SELECT
    parent.relname AS parent_table,
    child.relname  AS partition_name,
    pg_get_expr(child_part.relpartbound, child_part.oid) AS partition_range
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
JOIN pg_class child_part ON child_part.oid = child.oid
WHERE parent.relname = 'job_postings_partitioned';

-- Task 6: Detach and drop an old partition (fast — no row-by-row delete)
-- ALTER TABLE job_postings_partitioned DETACH PARTITION job_postings_2023_q1;
-- DROP TABLE job_postings_2023_q1;
