---
date: 2026-10-06
phase: python
topic: Exception handling: custom exceptions and error context
---

# Exception handling: custom exceptions and error context

*Python for data engineering*

## Concept

Custom exceptions in data pipelines allow you to surface domain-specific errors with rich context, making failures debuggable and recoverable. Instead of catching generic `ValueError` or `KeyError`, you define exceptions that capture *what* failed and *why*—salary out of range, malformed date, missing required field—so downstream handlers (logging, alerting, retry logic) can respond appropriately. Without this, errors propagate as cryptic tracebacks; with it, your pipeline logs tell you exactly which record failed parsing, which schema validation rule was violated, and what the bad value was.

This matters most when processing semi-trusted data (APIs, user uploads, database exports) where you expect occasional bad rows but need to keep the pipeline running. A single corrupted salary field shouldn't crash your entire ETL; it should be logged, the row skipped or quarantined, and processing continues. Custom exceptions let you catch and handle failures at the right level—retry a record, log it to a dead-letter table, alert an analyst—rather than restarting the entire job.

## Practice

**Problem:** Your ETL loads `job_postings_fact` from an external API. About 2% of records have `salary_year_avg` as a string ("$150K"), missing entirely, or nonsensical (negative). Standard parsing will crash on mixed types. You need to validate, coerce, and track failures without halting the pipeline.

```python
class SalaryValidationError(ValueError):
    """Raised when salary_year_avg cannot be parsed or is out of valid range."""
    def __init__(self, job_id: int, raw_value: any, reason: str):
        self.job_id = job_id
        self.raw_value = raw_value
        self.reason = reason
        super().__init__(
            f"job_id={job_id}: salary validation failed. "
            f"raw_value={raw_value!r}, reason={reason}"
        )

def parse_salary(job_id: int, raw_salary: any) -> float:
    """Parse and validate salary. Raises SalaryValidationError with context."""
    if raw_salary is None:
        raise SalaryValidationError(job_id, raw_salary, "missing value")
    
    # Coerce string to float
    if isinstance(raw_salary, str):
        try:
            cleaned = raw_salary.replace("$", "").replace(",", "").strip()
            parsed = float(cleaned)
        except ValueError:
            raise SalaryValidationError(job_id, raw_salary, "cannot parse as number")
    else:
        parsed = float(raw_salary)
    
    # Range check
    if parsed < 0:
        raise SalaryValidationError(job_id, parsed, "negative salary")
    if parsed > 1_000_000:
        raise SalaryValidationError(job_id, parsed, "implausibly high (>$1M)")
    
    return parsed

# In your pipeline:
dead_letter_rows = []
for row in api_response:
    try:
        clean_salary = parse_salary(row["job_id"], row["salary_year_avg"])
        # Insert validated row
    except SalaryValidationError as e:
        logger.warning(f"Skipping row: {e}")
        dead_letter_rows.append({"job_id": e.job_id, "error": e.reason, "raw_value": e.raw_value})
        continue

# Log dead-letter table for review
if dead_letter_rows:
    insert_into_table("job_postings_dead_letter", dead_letter_rows)
```

## Notes

- **Avoid bare `except:`** — Always catch the specific exception type you expect (e.g., `SalaryValidationError`). Generic catch-alls hide bugs and mask unrelated failures (e.g., out-of-memory errors).
- **Store context in the exception object**, not just in the message. This lets handlers access `job_id`, `raw_value`, etc. programmatically without string parsing.
- **Dead-letter tables are your friend** — Instead of raising and failing, log bad rows to a separate table for manual inspection. Analysts can then fix source data or refine validation rules.
- **Connect to schema validation** — Custom exceptions pair well with Pydantic or Great Expectations: validation failures become typed, structured errors that trigger specific recovery paths.
- **Revisit error budgets** — Define thresholds (e.g., "fail the job if >5% of records fail validation"). Track error rates over time to detect degradation in upstream data quality.
