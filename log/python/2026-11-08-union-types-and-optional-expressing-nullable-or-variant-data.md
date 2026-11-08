---
date: 2026-11-08
phase: python
topic: Union types and Optional: expressing nullable or variant data
---

# Union types and Optional: expressing nullable or variant data

*Python for data engineering*

## Concept

Union types and Optional allow you to express that a value *might not exist* or *could be one of several types*. In Python, `Optional[T]` is shorthand for `Union[T, None]`, telling both the type checker and future readers that `None` is a valid value. This matters in data pipelines because real data is messy—salary fields are missing, location might be remote (null) or a city name, API responses fail—and pretending every field is always populated causes runtime crashes or silent data corruption.

Without explicit typing, a function accepting a salary might crash when it receives `None`, or worse, silently compute wrong aggregates. With `Optional[str]` or `Union[str, int]`, you force the code to *acknowledge* the possibility and handle it. Type checkers like mypy will warn you if you use an Optional value without checking for None first, catching bugs before they reach production. This becomes critical in ETL jobs where bad input is guaranteed.

## Practice

**Problem:** Write a function that extracts job location from the `job_postings_fact` table. A location is either a city string (e.g. "New York") or None if the job is fully remote (indicated by `job_work_from_home = TRUE`). The function must handle both cases and a downstream aggregation needs to count jobs by location—including remote jobs under a "Remote" category.

```python
from typing import Optional, Union

def normalize_job_location(
    job_location: Optional[str],
    is_remote: bool
) -> str:
    """
    Return normalized location for reporting.
    
    Args:
        job_location: City/location string or None
        is_remote: Whether job_work_from_home is TRUE
    
    Returns:
        Location string: either the city, "Remote", or "Unknown"
    """
    if is_remote:
        return "Remote"
    if job_location is None:
        return "Unknown"
    return job_location.strip()

# Usage in pipeline
locations = [
    normalize_job_location("New York", False),           # → "New York"
    normalize_job_location(None, True),                  # → "Remote"
    normalize_job_location(None, False),                 # → "Unknown"
]
```

## Notes

- **Common mistake:** passing `Optional[T]` to a function and forgetting to check for None before using it. Type checkers catch this; trust their warnings.
- **Union for variants:** Use `Union[str, int]` when a field genuinely has multiple types (e.g., salary could be annual int or hourly string); consider normalizing early in your pipeline instead.
- **Database nulls → Python None:** Always map SQL `NULL` to Python `None`, not empty strings or 0—they have different meanings and silently swapping them causes incorrect aggregations.
- **Pattern matching:** Python 3.10+ `match` statements make handling Unions elegant; see PEP 634.
- **Related:** dataclass validation with `pydantic` enforces Optional/Union rules at deserialization time, catching bad input from APIs or files before it reaches your logic.
