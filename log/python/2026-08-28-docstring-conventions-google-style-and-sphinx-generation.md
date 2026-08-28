---
date: 2026-08-28
phase: python
topic: Docstring conventions: Google style and Sphinx generation
---

# Docstring conventions: Google style and Sphinx generation

*Python for data engineering*

## Concept

Google-style docstrings provide structured, human-readable documentation that tools like Sphinx can automatically parse into API documentation. They specify purpose, arguments, return values, and exceptions in a consistent format, making code self-documenting without requiring separate documentation files. In data pipelines, clear docstrings are critical because functions often transform schema-dependent data; a missing parameter description or return type can cause downstream jobs to fail silently or produce wrong results.

Without docstrings, data engineering teams lose the ability to auto-generate schema documentation, making it harder to onboard new engineers and debug pipeline failures. Type hints alone aren't enough—a function may accept `List[dict]` but the docstring clarifies what keys those dicts must contain and what salary values mean (gross vs. net, annualized vs. hourly). Sphinx integration turns docstrings into searchable HTML docs that stay synchronized with code, preventing the "documentation is always out of date" problem.

## Practice

**Problem:** Write a typed, Google-style docstring for a function that filters and transforms job postings, handling missing or invalid salary data gracefully.

```python
def filter_remote_jobs_by_salary(
    job_postings: list[dict],
    min_salary: float | None = None,
    max_salary: float | None = None,
) -> list[dict]:
    """Filter job postings by remote eligibility and salary range.
    
    Processes rows from job_postings_fact, returning only remote positions
    within the specified salary band. Rows with NULL or malformed salary_year_avg
    are excluded from results.
    
    Args:
        job_postings: List of job posting dicts with keys: job_id (int), 
            job_title_short (str), salary_year_avg (float | None), 
            job_work_from_home (bool), job_posted_date (date), 
            job_location (str).
        min_salary: Minimum annual salary (USD) to include. Defaults to None 
            (no lower bound).
        max_salary: Maximum annual salary (USD) to include. Defaults to None 
            (no upper bound).
    
    Returns:
        List of filtered job posting dicts, sorted by salary_year_avg descending.
        Empty list if no matches found.
    
    Raises:
        TypeError: If job_postings is not a list or contains non-dict elements.
        ValueError: If min_salary > max_salary.
    
    Example:
        >>> jobs = [{'job_id': 1, 'salary_year_avg': 120000, 'job_work_from_home': True}]
        >>> filter_remote_jobs_by_salary(jobs, min_salary=100000)
        [{'job_id': 1, 'salary_year_avg': 120000, 'job_work_from_home': True}]
    """
    if not isinstance(job_postings, list):
        raise TypeError("job_postings must be a list")
    if min_salary is not None and max_salary is not None and min_salary > max_salary:
        raise ValueError("min_salary cannot exceed max_salary")
    
    filtered = [
        job for job in job_postings
        if job.get('job_work_from_home') is True
        and job.get('salary_year_avg') is not None
        and (min_salary is None or job['salary_year_avg'] >= min_salary)
        and (max_salary is None or job['salary_year_avg'] <= max_salary)
    ]
    return sorted(filtered, key=lambda x: x['salary_year_avg'], reverse=True)
```

## Notes

- **Common mistake:** Omitting return type in Args/Returns sections or using vague descriptions like "data" or "result"—always name the exact schema keys and types downstream code expects.
- **Schema coupling:** Data pipeline functions are tightly bound to table schemas; docstrings should explicitly list required dict keys and their types so breaking schema changes are caught during code review.
- **Sphinx setup:** Configure `conf.py` with `extensions = ['sphinx.ext.autodoc']` and run `sphinx-apidoc -o docs src/` to auto-generate `.rst` files from docstrings; regenerate docs in CI/CD.
- **Type hints + docstrings:** Use both—type hints catch static errors, docstrings document *semantic* meaning (e.g., salary is annualized USD, not hourly or EUR).
- **Testing docstring examples:** Enable doctest mode (`pytest --doctest-modules`) to verify Example blocks in docstrings stay correct as code evolves.
