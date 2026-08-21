---
date: 2026-08-21
phase: python
topic: TypeVar and Generic for reusable typed containers
---

# TypeVar and Generic for reusable typed containers

*Python for data engineering*

## Concept

TypeVar and Generic enable you to write container classes and functions that work with multiple types while preserving type information at runtime and in your IDE. Without them, you either lose type hints (using `Any`) or repeat the same logic for each type. In data pipelines, this matters because you handle heterogeneous data—batches of rows, cached results, validation results—all following the same structural pattern but holding different payloads.

The problem: a `CachedResult` class that wraps a list of job posting dictionaries needs the same validation logic as a `CachedResult` wrapping validation errors. If you write it once with `Any`, mypy won't catch when you accidentally treat a list of dicts like a list of strings. If you write separate classes, you duplicate boilerplate. TypeVar + Generic solve this by letting one class adapt its type signature to what you actually store.

Without proper typing, pipeline stages don't compose safely. A function expecting `CachedResult[list[dict]]` will accept `CachedResult[str]` at runtime, and you'll discover the mismatch during a production ETL run when transformation code tries to iterate over a string.

## Practice

**Problem:** Write a reusable `DataCache` class that safely stores query results (dictionaries), validation reports (lists of strings), or row counts (integers). Different downstream stages expect different types; caching must preserve type hints so calling code knows what it receives.

```python
from typing import TypeVar, Generic, Optional
from datetime import datetime

T = TypeVar('T')

class DataCache(Generic[T]):
    """Type-safe cache for pipeline results."""
    
    def __init__(self, data: T, query: str):
        self._data: T = data
        self._query = query
        self._cached_at = datetime.now()
    
    def get(self) -> T:
        return self._data
    
    def is_stale(self, ttl_seconds: int = 3600) -> bool:
        return (datetime.now() - self._cached_at).seconds > ttl_seconds


# Usage in pipeline stages
results: DataCache[list[dict]] = DataCache(
    data=[{"job_id": 1, "salary_year_avg": 95000}],
    query="SELECT * FROM job_postings_fact WHERE job_work_from_home = true"
)

# Type checker knows results.get() returns list[dict], not Any
job_rows = results.get()
first_salary = job_rows[0]["salary_year_avg"]  # ✓ type-safe

errors: DataCache[list[str]] = DataCache(
    data=["Row 5: invalid date", "Row 12: null salary"],
    query="validation_check"
)

# Type checker knows errors.get() returns list[str]
for msg in errors.get():
    print(msg)
```

## Notes

- **Bound TypeVars** (`T = TypeVar('T', bound=BaseClass)`) restrict what types T can be; useful when your generic class needs to call specific methods on the stored data.
- **Covariance gotcha**: `DataCache[int]` is not a subtype of `DataCache[object]` even though `int` is a subtype of `object`; use `Generic[+T]` notation in type stubs if you need covariance, but avoid it in mutable containers.
- **Runtime erasure**: generics are stripped at runtime (you can't do `if isinstance(x, list[dict])`); keep validation in `__init__` or use `pydantic` models for runtime checks.
- **Adjacent skills**: Protocol (structural typing), dataclass + Generic (cleaner than manual `__init__`), and Callable typing for factory functions that return parameterized containers.
- **Revisit**: when adding Generic to existing pipeline utility classes (e.g., `BatchProcessor`, `ValidationResult`), check all call sites for `Any` annotations that can now be replaced with concrete type parameters.
