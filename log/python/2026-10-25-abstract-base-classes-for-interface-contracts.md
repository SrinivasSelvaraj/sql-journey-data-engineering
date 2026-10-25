---
date: 2026-10-25
phase: python
topic: Abstract base classes for interface contracts
---

# Abstract base classes for interface contracts

*Python for data engineering*

## Concept

An abstract base class (ABC) defines an interface contract that subclasses must fulfill. In Python, use `abc.ABC` and `@abstractmethod` to enforce that child classes implement required methods. This matters in data pipelines because extractors, transformers, and loaders often share behavior patterns—defining an ABC prevents someone from instantiating an incomplete loader or forgetting to implement a critical validation step.

Without ABCs, you discover missing methods at runtime, deep in a job DAG, after data has partially processed. With ABCs, the contract is checked at import time. For example, all extractors should implement `fetch()` and `validate_schema()`, but a CSV extractor might skip validation if no interface enforces it, causing silent data quality failures downstream.

## Practice

**Problem:** You have multiple data sources (APIs, databases, CSV files) feeding a fact table. Each source needs to extract, transform, and land data, but developers keep forgetting to implement error handling or schema validation. You need a contract that forces every source handler to validate row counts and null distributions before insert.

```python
from abc import ABC, abstractmethod
from typing import List, Dict

class DataSourceHandler(ABC):
    @abstractmethod
    def extract(self) -> List[Dict]:
        pass
    
    @abstractmethod
    def validate(self, rows: List[Dict]) -> bool:
        pass
    
    @abstractmethod
    def load(self, rows: List[Dict]) -> int:
        pass

class JobPostingsLoader(DataSourceHandler):
    def extract(self) -> List[Dict]:
        # fetch from API or DB
        return [{"job_id": 1, "job_title_short": "Engineer", ...}]
    
    def validate(self, rows: List[Dict]) -> bool:
        # enforce: no null job_id, salary_year_avg > 0, job_posted_date not future
        for row in rows:
            if not row.get("job_id") or row.get("salary_year_avg", 0) <= 0:
                raise ValueError(f"Invalid row: {row}")
        return True
    
    def load(self, rows: List[Dict]) -> int:
        # INSERT into job_postings_fact after validation
        self.validate(rows)
        return len(rows)

# This fails at class definition, not at runtime:
# class IncompleteLoader(DataSourceHandler):
#     def extract(self): pass
# TypeError: Can't instantiate abstract class IncompleteLoader without validate, load
```

## Notes

- **Mistake:** Defining ABC but not actually using `@abstractmethod`—creates false security that subclasses implemented everything.
- **Mistake:** Over-abstracting; don't create an ABC for one-off loaders. Wait until you have 2–3 similar classes before extracting a contract.
- **Connects to:** dataclass validation (`pydantic.BaseModel` for row schemas), type hints (`Protocol` as an alternative to ABC for duck typing), and pytest fixtures (inject handlers to test multiple implementations identically).
- **Revisit:** `@property` and `@abstractmethod` stacked; `isinstance()` checks before calling abstract methods; how ABCs interact with `__init_subclass__` for auto-registration of handlers.
