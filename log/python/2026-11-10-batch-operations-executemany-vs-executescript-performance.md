---
date: 2026-11-10
phase: python
topic: Batch operations: executemany vs executescript performance
---

# Batch operations: executemany vs executescript performance

*Python for data engineering*

## Concept

`executemany()` and `executescript()` are two different SQLite execution methods with fundamentally different purposes and performance characteristics. `executemany()` is designed for bulk DML operations—it takes a single SQL statement with placeholders and executes it repeatedly against multiple parameter sets, ideal for INSERT/UPDATE/DELETE batches. `executescript()` bypasses parameterization entirely and executes raw SQL strings sequentially, typically used for DDL (CREATE TABLE, indexes) or schema setup, but dangerous for user input.

The performance difference matters acutely when loading data at scale. `executemany()` maintains a prepared statement in memory and reuses its query plan for each iteration, reducing parsing overhead dramatically. For inserting 10,000 rows, `executemany()` typically outperforms looped individual `execute()` calls by 10–50×. `executescript()` is slower for repetitive DML because it re-parses each statement, but it's necessary when you need multiple statements in one call (transactions, DDL chains).

Without understanding this distinction, pipelines suffer two failures: (1) performance bottlenecks when loading fact tables—a loop of individual `execute()` calls on 1M rows can take hours instead of minutes—and (2) SQL injection vulnerabilities when using `executescript()` with untrusted data like user-provided job titles or locations, since it ignores parameterization entirely.

## Practice

**Problem:** Load 50,000 job posting records into `job_postings_fact` from a staging table or API response. The naive approach loops individual `execute()` calls; you need the performant, safe bulk method.

```sql
-- NAIVE (slow, risky if data comes from user input):
-- for row in job_data:
--     cursor.execute(
--         "INSERT INTO job_postings_fact VALUES (?, ?, ?, ?, ?, ?)",
--         (row['job_id'], row['title'], row['salary'], row['wfh'], row['date'], row['location'])
--     )

-- CORRECT (executemany):
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES (?, ?, ?, ?, ?, ?);

-- In Python:
job_data = [
    (1001, 'Data Engineer', 95000, True, '2024-01-15', 'Remote'),
    (1002, 'Analytics Lead', 110000, False, '2024-01-16', 'New York, NY'),
    # ... 49,998 more rows
]

cursor.executemany(
    """INSERT INTO job_postings_fact 
       (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
       VALUES (?, ?, ?, ?, ?, ?)""",
    job_data
)
conn.commit()
```

## Notes

- **Parameterization is mandatory for `executemany()`**—the `?` placeholders prevent SQL injection even if `job_title_short` contains quotes or malicious strings. `executescript()` has no such protection and should never touch user-controlled data.

- **`executemany()` requires the SQL string to be identical across all iterations**—only parameter values change. If your INSERT logic varies per row, fall back to looped `execute()` or refactor to a CASE/UNION pattern.

- **Transaction scope matters**—wrap `executemany()` in explicit `BEGIN/COMMIT` for maximum speed; automatic commits per statement are the hidden killer. Use `conn.commit()` once after the batch, not per iteration.

- **This pattern connects to batch size tuning** and memory trade-offs: passing all 50K rows at once is fastest but risky for OOM on large datasets; chunk into batches of 5K–10K rows and commit periodically for stability.

- **Adjacent skill**: learn `executescript()` for schema DDL (creating tables, indexes) in setup phases, but never mix it with data loading from untrusted sources—always use parameterized DML for the actual ETL pipeline.
