---
date: 2026-11-10
phase: python
topic: Sqlalchemy Core: raw SQL execution and type handling
---

# Sqlalchemy Core: raw SQL execution and type handling

*Python for data engineering*

## Concept

SQLAlchemy Core's raw SQL execution (`text()`, `execute()`) lets you run parameterized queries when ORM abstraction is too restrictive or when you need direct control over query shape—critical for ETL pipelines where performance and predictability matter. Type handling becomes essential because SQLAlchemy must convert between Python types and database types; without explicit type hints, you risk silent data loss (e.g., a float truncated to integer) or runtime crashes when NULL values arrive unexpectedly.

Raw SQL execution matters most when: (1) you're loading denormalized fact tables where complex window functions or CTEs are clearer than ORM chains, (2) you need bulk inserts with specific constraints that bypassed ORM validation, or (3) you're filtering on computed columns that don't map cleanly to model attributes. Type mismatches break silently—a salary_year_avg arriving as string instead of integer will fail downstream aggregations, and job_posted_date as text breaks date arithmetic in transforms.

Using `text()` with explicit parameter binding and `types` module protections makes your pipeline robust: it prevents SQL injection, makes type intent visible in code review, and lets you catch schema drift early.

## Practice

**Problem:** Load job postings from a CSV into job_postings_fact, filtering for remote work only and validating salary is numeric. You need to insert only rows where job_posted_date is after 2023-01-01, handling NULL salaries as 0.

```sql
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES 
  (:job_id, :job_title_short, COALESCE(:salary_year_avg, 0), :job_work_from_home, :job_posted_date, :job_location)
WHERE 
  job_work_from_home = TRUE 
  AND job_posted_date > '2023-01-01'
  AND (salary_year_avg IS NULL OR salary_year_avg > 0);
```

**Python equivalent with type safety:**
```python
from sqlalchemy import text, Integer, String, Boolean, Date
from datetime import date

stmt = text("""
    INSERT INTO job_postings_fact 
    (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
    VALUES 
    (:job_id, :job_title_short, COALESCE(:salary_year_avg, 0), :job_work_from_home, :job_posted_date, :job_location)
""").bindparams(
    job_id=String(),
    job_title_short=String(),
    salary_year_avg=Integer(),
    job_work_from_home=Boolean(),
    job_posted_date=Date(),
    job_location=String()
)

connection.execute(stmt, {
    "job_id": "123",
    "job_title_short": "Data Engineer",
    "salary_year_avg": 120000,
    "job_work_from_home": True,
    "job_posted_date": date(2023, 6, 15),
    "job_location": "Remote"
})
```

## Notes

- **Named parameters with `:param` syntax** are safer than f-strings; SQLAlchemy handles escaping and prevents injection attacks even with raw SQL.
- **`bindparams()` is declarative type insurance**—it fails fast if you pass a string where an Integer is bound, catching bugs before they hit the database.
- **NULL handling is implicit ambiguity**: ORM attributes default to nullable=True, but `text()` queries won't warn you. Always wrap suspect columns in `COALESCE()` or validate upstream in Python.
- **Type coercion across dialects varies** (PostgreSQL's CAST vs MySQL's CONVERT); document dialect assumptions or use SQLAlchemy's `cast()` function when possible to stay portable.
- **Adjacent topics**: result row type mapping (use `Row.keys()` to inspect schema), connection pooling strategy for bulk loads, and schema validation fixtures for integration tests.
