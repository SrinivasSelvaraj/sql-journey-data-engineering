---
date: 2026-11-07
phase: sql
topic: SQL injection: parameterized queries and prepared statements
---

# SQL injection: parameterized queries and prepared statements

*SQL for analytics and engineering*

## Concept

SQL injection occurs when untrusted user input is concatenated directly into SQL query strings, allowing attackers to inject arbitrary SQL commands. For example, if a search parameter like `'; DROP TABLE users; --` is concatenated into a query, the database executes unintended statements. In analytics and data engineering, this is critical when building APIs, dashboards, or ETL pipelines that accept user filters—even internal tools can be vulnerable if developers forget sanitization.

Parameterized queries (also called prepared statements) solve this by separating SQL logic from data. The query structure is defined first with placeholders (e.g., `?` or `$1`), and parameter values are sent separately to the database driver. The database treats all parameter values as literal data, never as executable code, making injection impossible regardless of input content.

Without parameterization, every dynamic query becomes a security liability. In production pipelines handling millions of records, a single compromised filter parameter can corrupt data, expose sensitive information, or halt operations. Even in read-only analytics contexts, injection can leak schema details or force expensive, malicious queries that crash the system.

## Practice

**Problem:** Build a query that accepts a user-provided job title substring and salary threshold as filters. Without parameterization, the query is vulnerable to injection. Rewrite it safely.

**Vulnerable (unsafe):**
```sql
-- DO NOT USE IN PRODUCTION
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_title_short LIKE '%' + @title_input + '%'
  AND salary_year_avg > @salary_input;
```

**Safe (parameterized):**
```sql
-- Python example using parameterized query
DECLARE @title_param NVARCHAR(255) = ?;
DECLARE @salary_param INT = ?;

SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_title_short LIKE '%' + @title_param + '%'
  AND salary_year_avg > @salary_param;

-- When called from Python/application code:
-- cursor.execute(query, (user_title_input, user_salary_input))
-- The driver ensures values are escaped and treated as literals.
```

## Notes

- **Parameter syntax varies by database and language:** SQL Server uses `@name`, PostgreSQL uses `$1/$2`, MySQL uses `?`. Always check your driver's documentation (psycopg2, sqlalchemy, ODBC, etc.).
- **LIKE wildcards must still be handled carefully:** The `%` and `_` are added in application logic before parameterization, not concatenated into the query string. If users can control wildcards, escape them or validate separately.
- **Prepared statements offer a bonus:** Caching the query plan on the server side can improve performance when the same query runs repeatedly with different parameters.
- **This connects to API and ETL security:** Any pipeline that reads user input—filters in a Slack bot, URL query params in a dashboard, values from a configuration file—must use parameterization. Treat all external input as hostile.
- **Revisit in context of ORM frameworks:** ORMs like SQLAlchemy, Django ORM, and Hibernate handle parameterization automatically when you use their query builders correctly. Misuse (e.g., string formatting in ORM filters) reintroduces the vulnerability.
