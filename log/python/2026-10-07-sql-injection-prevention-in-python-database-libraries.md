---
date: 2026-10-07
phase: python
topic: SQL injection prevention in Python database libraries
---

# SQL injection prevention in Python database libraries

*Python for data engineering*

## Concept

SQL injection occurs when untrusted user input is concatenated directly into SQL query strings, allowing attackers to execute arbitrary SQL commands. In Python data pipelines, this is critical because pipelines often ingest external data (API responses, user uploads, config files) and use it to construct queries. Without parameterized queries, a malicious job title like `'; DROP TABLE job_postings_fact; --` gets interpreted as executable SQL rather than a literal string value.

All major Python database libraries (`psycopg2`, `sqlite3`, `mysql-connector-python`, `sqlalchemy`) provide parameterized query mechanisms—using placeholders and passing values separately—that ensure input is treated as data, never as code. This is your first defense. Relying on string formatting, f-strings, or `.format()` for SQL is unsafe, even if you add manual escaping.

## Practice

**Problem:** Write a query that filters job postings by location without risk of injection. User input is an untrusted location string like `"New York"` or malicious input like `"New York' OR '1'='1`.

**Unsafe (vulnerable):**
```sql
query = f"SELECT * FROM job_postings_fact WHERE job_location = '{user_location}'"
```

**Safe (parameterized):**
```python
import psycopg2

user_location = "New York"  # or any untrusted input
conn = psycopg2.connect("dbname=jobs user=analyst")
cursor = conn.cursor()

cursor.execute(
    "SELECT job_id, job_title_short, salary_year_avg FROM job_postings_fact WHERE job_location = %s",
    (user_location,)
)
results = cursor.fetchall()
```

The `%s` placeholder and tuple `(user_location,)` tell the driver to safely escape and bind the value. SQLAlchemy ORM and `with_entities().filter()` handle this automatically.

## Notes

- **String concatenation is never acceptable** for SQL, even with `.strip()`, `.replace()`, or custom validation—use parameterized queries always.
- **Type hints don't prevent injection**; a function typed `filter_by_location(loc: str)` is still vulnerable if `loc` reaches an unparameterized query.
- **Stored procedures also require parameters**: calling `CALL sp_filter_jobs(?)` with bound parameters is safe; building the call string is not.
- **Adjacent concern:** input validation and schema validation are separate layers—validate *what* data you accept (domain logic), but parameterization is *how* you safely pass it to SQL.
- **Revisit in context of:** ORMs (SQLAlchemy/Django ORM hide parameterization but can be bypassed with raw SQL), logging (never log raw query strings with actual values), and testing (mock databases to verify parameterized calls, not string output).
