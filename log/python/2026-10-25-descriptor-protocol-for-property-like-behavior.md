---
date: 2026-10-25
phase: python
topic: Descriptor protocol for property-like behavior
---

# Descriptor protocol for property-like behavior

*Python for data engineering*

## Concept

The descriptor protocol in Python allows you to intercept and customize attribute access on objects via `__get__`, `__set__`, and `__delete__` methods. When a descriptor is assigned to a class attribute, Python calls these methods instead of returning the descriptor object itself, enabling computed properties, validation, and lazy loading without explicit method calls. This matters in data pipelines because it lets you enforce type safety and transformation rules at the point of assignment—catching bad input early rather than deep in downstream transformations.

Without descriptors, you either accept raw untrusted values into your data structures or wrap every access in validation methods, which is verbose and easy to bypass. Descriptors are especially valuable when building ETL intermediate objects that must validate salary ranges, enforce date formats, or ensure nullable fields actually match their schema before being written to a warehouse. They survive bad input by raising clear exceptions at assignment time, not query time.

## Practice

**Problem:** Your `job_postings_fact` loader accepts CSV rows as dictionaries. You need to validate that `salary_year_avg` is numeric and non-negative, `job_posted_date` parses as a valid date, and `job_work_from_home` is strictly boolean—all without littering the loader with try-except blocks.

```python
from datetime import datetime
from typing import Any

class ValidatedInt:
    """Descriptor that enforces non-negative integers."""
    def __init__(self, name: str, allow_none: bool = True):
        self.name = name
        self.allow_none = allow_none
    
    def __set_name__(self, owner, name):
        self.name = name
    
    def __get__(self, obj, objtype=None):
        return obj.__dict__.get(self.name, None)
    
    def __set__(self, obj, value):
        if value is None and self.allow_none:
            obj.__dict__[self.name] = None
            return
        if not isinstance(value, int):
            raise TypeError(f"{self.name} must be int, got {type(value).__name__}")
        if value < 0:
            raise ValueError(f"{self.name} must be non-negative, got {value}")
        obj.__dict__[self.name] = value

class ValidatedDate:
    """Descriptor that enforces valid ISO date strings."""
    def __init__(self, name: str, allow_none: bool = True):
        self.name = name
        self.allow_none = allow_none
    
    def __set_name__(self, owner, name):
        self.name = name
    
    def __get__(self, obj, objtype=None):
        return obj.__dict__.get(self.name, None)
    
    def __set__(self, obj, value):
        if value is None and self.allow_none:
            obj.__dict__[self.name] = None
            return
        if isinstance(value, str):
            try:
                datetime.fromisoformat(value)
                obj.__dict__[self.name] = value
            except ValueError:
                raise ValueError(f"{self.name} must be ISO date string, got {value}")
        else:
            raise TypeError(f"{self.name} must be str, got {type(value).__name__}")

class JobPostingFact:
    salary_year_avg = ValidatedInt("salary_year_avg", allow_none=True)
    job_posted_date = ValidatedDate("job_posted_date", allow_none=False)
    
    def __init__(self, job_id: int, job_title_short: str, salary_year_avg: int | None,
                 job_work_from_home: bool, job_posted_date: str, job_location: str):
        self.job_id = job_id
        self.job_title_short = job_title_short
        self.salary_year_avg = salary_year_avg
        self.job_work_from_home = job_work_from_home
        self.job_posted_date = job_posted_date
        self.job_location = job_location

# Usage: bad input raises immediately during construction
try:
    row = JobPostingFact(1, "Data Engineer", -50000, True, "2024-01-15", "Remote")
except ValueError as e:
    print(f"Pipeline stopped: {e}")  # "salary_year_avg must be non-negative, got -50000"
```

## Notes

- **Descriptor assignment happens at class definition time**, not instance time—use `__set_name__` to capture the attribute name automatically and avoid redundant string literals that get out of sync.
- **Properties vs. descriptors:** `@property` is a built-in descriptor for read-mostly access; write your own descriptor when you need `__set__` validation or shared logic across multiple attributes.
- **Instance dict pollution:** Store values in `obj.__dict__[name]` rather than as instance attributes to avoid infinite recursion when `__get__` or `__set__` calls itself.
- **Pair descriptors with type hints
