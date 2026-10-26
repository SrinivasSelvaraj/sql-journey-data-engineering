---
date: 2026-10-26
phase: python
topic: Typing.TypeVar and generic pipeline functions
---

# Typing.TypeVar and generic pipeline functions

*Python for data engineering*

## Concept

`TypeVar` lets you write generic functions that work with multiple types while preserving type information through the pipeline. Instead of accepting `Any`, you define a type variable that stays consistent across inputs and outputs—your function receives a list of strings and returns a list of strings, not `Any`. This matters in data pipelines because each transformation step must know what shape of data it's handling; without generics, you lose type hints between stages and miss errors at development time, not in production.

Without `TypeVar`, you either annotate everything as `Any` (defeating the purpose of typing) or write duplicate functions for each type. A concrete case: a function that filters and deduplicates job records should preserve the knowledge that "I accept job dictionaries and return job dictionaries," not "I accept something and return something." This matters when the next pipeline stage expects specific keys like `job_id` or `salary_year_avg`—type checkers catch missing fields only if the type flows through.

## Practice

**Problem:** Write a reusable pipeline function that filters a list of job records by a boolean field, but only if that field exists. The function should accept any flat dictionary and return the same dictionary type, and should fail at type-check time if you pass non-dict records.

```python
from typing import TypeVar, Callable

T = TypeVar('T', bound=dict)

def filter_by_boolean_field(
    records: list[T],
    field_name: str,
    value: bool
) -> list[T]:
    """Filter records where field_name == value. Preserves input type."""
    return [r for r in records if r.get(field_name) is value]

# Usage:
jobs: list[dict[str, str | bool | float]] = [
    {"job_id": 1, "job_title_short": "Data Engineer", "job_work_from_home": True, "salary_year_avg": 95000},
    {"job_id": 2, "job_title_short": "Analyst", "job_work_from_home": False, "salary_year_avg": 75000},
]

remote_jobs = filter_by_boolean_field(jobs, "job_work_from_home", True)
# Type checker knows remote_jobs has the same dict structure as jobs
```

## Notes

- **Bound parameter**: `TypeVar('T', bound=dict)` ensures `T` must be a dict subclass; this prevents passing integers or strings and keeps the contract tight.
- **Lost specificity**: Even with `TypeVar`, Python's dict type hint doesn't capture key names—use `TypedDict` from `typing` if you need to enforce exact schema (e.g., `job_id` must exist).
- **Generic vs. overload**: Use `TypeVar` for "same type in, same type out"; use `@overload` when inputs and outputs follow different type patterns (e.g., accept str or list, return different things).
- **Common mistake**: Forgetting that `TypeVar` only works at check time—`get()` and `.get(field_name)` still return `Any` unless you narrow the type with explicit checks or assertions.
- **Pipeline integration**: Pair with `Callable[[T], T]` signatures for transformer functions so that composing stages (`map(transform1) | map(transform2)`) maintains type safety end-to-end.
