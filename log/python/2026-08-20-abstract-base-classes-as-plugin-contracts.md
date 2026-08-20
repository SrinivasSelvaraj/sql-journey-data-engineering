---
date: 2026-08-20
phase: python
topic: Abstract base classes as plugin contracts
---

# Abstract base classes as plugin contracts

*Python for data engineering*

## Concept

An abstract base class (ABC) defines a contract—a set of methods that all subclasses must implement—without providing a complete implementation itself. In data pipelines, ABCs enforce that every extractor, transformer, or loader follows the same interface, making it impossible to accidentally use a half-built connector or forget a critical validation step. When you have multiple data sources (APIs, databases, CSV files), each needs its own adapter, but they all need to expose `extract()`, `validate()`, and `transform()` in consistent ways. Without ABCs, you discover mismatched signatures at runtime; with them, the type checker and the Python interpreter catch the mistake before the pipeline runs.

The core benefit is **plugin safety**: you can write orchestration code that works with *any* extractor that inherits from `BaseExtractor`, confident that it will have `execute(context: PipelineContext) -> DataFrame`. If someone writes a new job posting extractor tomorrow and forgets to implement `validate()`, they get an error the moment they try to instantiate it—not three hours into a production run.

## Practice

**Problem:** You are building a modular ETL system for job posting data. You have a `LinkedInExtractor` and a `GreenhouseExtractor`, each pulling from different APIs with different response shapes. Your orchestrator needs to apply consistent error handling, schema validation, and logging to any extractor without writing custom code for each source. How do you enforce that both extractors implement the same essential methods?

```python
from abc import ABC, abstractmethod
from typing import Dict, Any
from pydantic import BaseModel, ValidationError
import pandas as pd

class JobPostingSchema(BaseModel):
    job_id: str
    job_title_short: str
    salary_year_avg: float | None
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

class BaseJobExtractor(ABC):
    """Contract for all job posting sources."""
    
    @abstractmethod
    def extract(self) -> list[Dict[str, Any]]:
        """Fetch raw records from source."""
        pass
    
    @abstractmethod
    def validate(self, record: Dict[str, Any]) -> JobPostingSchema:
        """Convert and validate a single record."""
        pass
    
    def run(self) -> pd.DataFrame:
        """Template method: orchestrates extract → validate → load."""
        raw = self.extract()
        validated = []
        for record in raw:
            try:
                validated.append(self.validate(record).model_dump())
            except ValidationError as e:
                print(f"Skipped invalid record: {e}")
        return pd.DataFrame(validated)

class LinkedInExtractor(BaseJobExtractor):
    def extract(self) -> list[Dict[str, Any]]:
        # API call to LinkedIn Jobs
        return [{"id": "123", "title": "Senior Data Engineer", ...}]
    
    def validate(self, record: Dict[str, Any]) -> JobPostingSchema:
        return JobPostingSchema(
            job_id=record["id"],
            job_title_short=record["title"][:50],
            salary_year_avg=record.get("salary"),
            job_work_from_home=record.get("remote", False),
            job_posted_date=record["posted_at"],
            job_location=record["location"]
        )

# This will fail at class definition time if you forget a method:
class GreenhouseExtractor(BaseJobExtractor):
    def extract(self) -> list[Dict[str, Any]]:
        return []
    # Missing validate() → TypeError on instantiation
```

## Notes

- **Common mistake:** Defining ABCs but not actually enforcing them in tests or type checking; use `mypy --strict` and unit tests that instantiate each subclass to catch missing methods early.
- **Schema validation is separate from contract enforcement**: the ABC enforces method signatures; Pydantic enforces data shape. Use both—ABCs at the class level, Pydantic at the data level.
- **Template method pattern** (like `run()` above) often pairs with ABCs: the parent defines the workflow, subclasses fill in source-specific steps; reduces orchestration boilerplate.
- **Revisit:** dataclass factories and dependency injection; as plugins grow, you may need to parameterize extractors (credentials, pagination limits) without changing the contract itself.
- **Adjacent topic:** Protocol classes (`typing.Protocol`) offer structural subtyping instead of nominal; useful when you can't inherit from a shared base but want type safety anyway.
