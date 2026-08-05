-- Practice: Transactions & ACID
-- Task 1: Basic COMMIT — wrap inserts in a transaction

BEGIN;

INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg)
VALUES (99901, 'Data Engineer', 130000);

INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg)
VALUES (99902, 'Data Analyst', 95000);

COMMIT;

-- Task 2: ROLLBACK — undo changes when something goes wrong

BEGIN;

UPDATE job_postings_fact
SET salary_year_avg = 0
WHERE job_title_short = 'Data Engineer';

-- Oops — wrong update, cancel it
ROLLBACK;

-- Task 3: SAVEPOINT — partial rollback within a transaction

BEGIN;

INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg)
VALUES (99903, 'ML Engineer', 150000);

SAVEPOINT after_insert;

DELETE FROM job_postings_fact WHERE job_id = 99901;

-- Only roll back the delete, keep the insert
ROLLBACK TO SAVEPOINT after_insert;

COMMIT;

-- Task 4: Transaction isolation — check current isolation level
SHOW transaction_isolation;

-- Task 5: Read-only transaction (safe for reporting queries)
BEGIN TRANSACTION READ ONLY;

SELECT job_title_short, AVG(salary_year_avg)
FROM job_postings_fact
GROUP BY job_title_short;

COMMIT;
