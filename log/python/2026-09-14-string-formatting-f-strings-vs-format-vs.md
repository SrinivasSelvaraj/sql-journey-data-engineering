---
date: 2026-09-14
phase: python
topic: String formatting: f-strings vs format vs %
---

# String formatting: f-strings vs format vs %

*Python for data engineering*

## Concept

String formatting in Python affects code readability, performance, and safety—critical when building data pipelines that must be maintainable and handle edge cases. F-strings (Python 3.6+) are the modern standard: they're faster, more readable, and allow inline expressions. The older `%` operator and `.format()` method still appear in legacy code but are slower and more error-prone. In data engineering, you'll often construct SQL queries, log messages, and file paths; using the wrong method can introduce SQL injection vulnerabilities, make debugging harder, or cause unexpected type coercion.

Without deliberate choice, you'll either mix styles (confusing teammates), lose performance in tight loops (query generation, large batch logging), or create unsafe string interpolation. In pipelines processing millions of records, a slow string method compounds. More critically, when logging or constructing queries with untrusted input, weak formatting invites bugs: `f"SELECT * FROM users WHERE id = {user_id}"` is vulnerable if `user_id` isn't validated—though parameterized queries are the real defense.

## Practice

**Problem:** You're building a data quality check that logs failed records. A pipeline ingests job posting data; you need to log records where `salary_year_avg` is NULL or implausible (e.g., negative or >$500k). The log message should include job details and the validation rule violated, and remain readable when grepping logs.

```sql
-- Safe parameterized query (use ORM or db driver, not string formatting for SQL)
SELECT job_id, job_title_short, salary_year_avg, job_location, job_posted_date
FROM job_postings_fact
WHERE salary_year_avg IS NULL 
   OR salary_year_avg < 0 
   OR salary_year_avg > 500000
ORDER BY job_posted_date DESC
LIMIT 100;
```

```python
# Python logging using f-strings (correct)
failed_records = [
    {"job_id": 101, "title": "Data Engineer", "salary": -50000, "location": "Remote"},
    {"job_id": 102, "title": "Analyst", "salary": None, "location": "NYC"},
]

for record in failed_records:
    job_id = record["job_id"]
    title = record["title"]
    salary = record["salary"]
    location = record["location"]
    
    if salary is None:
        reason = "MISSING_SALARY"
    elif salary < 0:
        reason = "NEGATIVE_SALARY"
    else:
        reason = "SALARY_OUT_OF_RANGE"
    
    # F-string: readable, fast, type-safe
    log_msg = (
        f"VALIDATION_FAILED | job_id={job_id} | title={title} | "
        f"salary={salary} | location={location} | reason={reason}"
    )
    print(log_msg)
    # Output: VALIDATION_FAILED | job_id=101 | title=Data Engineer | salary=-50000 | location=Remote | reason=NEGATIVE_SALARY
```

## Notes

- **Avoid `%` operator in new code**: it's slower and harder to read with many arguments (e.g., `"x=%s, y=%s, z=%s" % (a, b, c)`); exception: legacy code you must not touch.
- **`.format()` is a middle ground**: safer than `%`, clearer than positional args, but slower than f-strings and allows less readable inline logic; use only if supporting Python <3.6.
- **F-strings enable expression logic**: `f"{salary:,.2f}"` formats floats, `f"{timestamp.isoformat()}"` calls methods inline—but keep expressions simple; complex logic belongs in variables.
- **SQL injection defense is parameterization, not formatting**: never interpolate user input into SQL strings, even with f-strings. Use `cursor.execute("SELECT * FROM t WHERE id = ?", (user_id,))` or ORM methods.
- **Connects to**: type hints (f-strings work fine with types, but they don't enforce them), logging best practices (structured logs via `logging.extra` beat formatted strings for parsing), and testing (ensure your format strings handle `None`, empty strings, and special characters).
