---
date: 2026-08-29
phase: python
topic: Circular import prevention and module organization
---

# Circular import prevention and module organization

*Python for data engineering*

## Concept

Circular imports occur when module A imports from module B, and module B imports from module A (directly or through a chain). In data pipelines, this typically happens when you have transformation logic, data models, and utility functions spread across files that reference each other. Without prevention, Python raises `ImportError` at runtime, often during pipeline initialization—exactly when you're trying to load configuration or instantiate extractors and loaders.

The problem intensifies in data engineering because pipelines grow organically: you extract data with one module, validate with another, transform with a third, and suddenly the validation module needs a schema definition that lives in the transform module, which needs a utility from validation. The circular dependency breaks both local testing and CI/CD deployments, and it's insidious because the code may work in isolation but fail in the orchestrator's import phase.

Prevention requires deliberate module organization: separate concerns into layers (data models, business logic, orchestration), use dependency injection to pass dependencies rather than importing them at module level, and move type hints into TYPE_CHECKING blocks when they'd otherwise trigger circular imports.

## Practice

**Problem:** You have a `models.py` defining `JobPosting` dataclass, a `validators.py` that imports `JobPosting` to validate rows, and a `loader.py` that imports both `JobPosting` and validation functions. The circular dependency prevents the pipeline from starting.

**Solution:** Restructure using TYPE_CHECKING and dependency injection:

```python
# models.py
from dataclasses import dataclass
from datetime import date
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from validators import JobValidator

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: float
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

# validators.py
from typing import TYPE_CHECKING
from datetime import date

if TYPE_CHECKING:
    from models import JobPosting

def validate_job_posting(row: dict) -> bool:
    return (
        isinstance(row.get("salary_year_avg"), (int, float)) and
        row["salary_year_avg"] > 0 and
        isinstance(row.get("job_work_from_home"), bool)
    )

# loader.py
from models import JobPosting
from validators import validate_job_posting

def load_jobs(data: list[dict]) -> list[JobPosting]:
    validated = [row for row in data if validate_job_posting(row)]
    return [JobPosting(**row) for row in validated]
```

The TYPE_CHECKING block is False at runtime, so imports inside never execute; type checkers still see the hints for static analysis.

## Notes

- **Avoid module-level imports of interdependent logic:** delay imports until function execution (inside function bodies) only as a last resort; prefer restructuring instead.
- **Dependency injection over mutual imports:** pass validators, transformers, and schemas as function arguments rather than importing them, making dependencies explicit and testable.
- **Separate models from logic:** keep dataclass/Pydantic models in their own module with minimal imports; let business logic import models, not the reverse.
- **TYPE_CHECKING pattern is Python 3.5+:** use it for type hints that would create cycles; the block is excluded at runtime but visible to mypy and pyright.
- **Related concepts worth revisiting:** lazy imports, __all__ exports for public APIs, and fixture scoping in pytest to avoid import-time side effects during testing.
