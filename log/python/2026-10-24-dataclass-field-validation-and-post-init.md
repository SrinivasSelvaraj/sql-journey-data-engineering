---
date: 2026-10-24
phase: python
topic: Dataclass field validation and post_init
---

# Dataclass field validation and post_init

*Python for data engineering*

## Concept

A dataclass is Python's lightweight alternative to hand-written `__init__` and `__repr__` methods. The `@dataclass` decorator auto-generates these from type hints, making your pipeline code cleaner and more testable. However, dataclasses don't validate data by default—a salary of -50000 or a null job_id will pass silently. The `__post_init__` method runs immediately after `__init__`, giving you a hook to validate fields before the object enters your pipeline. This matters because bad data caught early (at ingestion) prevents silent corruption downstream, where a negative salary might cause a join to fail mysteriously or an aggregate to report wrong totals. Without validation, pipeline bugs become detective work instead of prevention.

## Practice

**Problem:** You're loading job posting data into a pipeline. The raw CSV sometimes contains empty job_ids, negative salaries, and dates in the future. You need a dataclass that rejects invalid records at load time, raising a clear error message so they can be quarantined.

```python
from dataclasses import dataclass
from datetime import date
from typing import Optional

@dataclass
class JobPostingFact:
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[float]
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    def __post_init__(self):
        if self.job_id <= 0:
            raise ValueError(f"job_id must be positive, got {self.job_id}")
        if not self.job_title_short or not self.job_title_short.strip():
            raise ValueError("job_title_short cannot be empty")
        if self.salary_year_avg is not None and self.salary_year_avg < 0:
            raise ValueError(f"salary_year_avg cannot be negative, got {self.salary_year_avg}")
        if self.job_posted_date > date.today():
            raise ValueError(f"job_posted_date cannot be in future, got {self.job_posted_date}")
        if not self.job_location or not self.job_location.strip():
            raise ValueError("job_location cannot be empty")
```

Usage: wrap instantiation in try-except to log/quarantine bad rows without halting the entire pipeline.

## Notes

- **Don't validate in `__init__` directly**: use `__post_init__` to keep validation logic separate and readable.
- **Optional fields need care**: a salary of `None` is valid, but `-100` is not. Use `is not None` guards before numeric checks.
- **Raise early, raise clearly**: custom error messages with the actual bad value make debugging 100× faster when scanning logs.
- **Pairs with frozen=True**: `@dataclass(frozen=True)` prevents accidental mutation after validation—useful for immutable fact tables.
- **Connects to**: Pydantic (enterprise-grade validation), union types for multi-state fields, and integration tests that feed bad CSV rows to verify quarantine behavior.
