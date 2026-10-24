---
date: 2026-10-24
phase: python
topic: Type hints: Protocol and structural subtyping
---

# Type hints: Protocol and structural subtyping

*Python for data engineering*

## Concept

A `Protocol` in Python's `typing` module defines a structural contract—what methods or attributes an object must have—without requiring explicit inheritance. Unlike nominal typing (where `class Dog(Animal)` declares the relationship), structural typing says "if it walks and quacks like a duck, it's a duck." This matters in data pipelines where you receive data from external APIs, databases, or third-party libraries: you don't control their class hierarchies, but you need to guarantee they conform to your expectations before processing.

Without protocols, you either overfit to concrete types (brittle, tightly coupled) or use `Any` (defeats type checking). Protocols let you write functions that accept any object providing `fetch()` and `transform()`, making your pipeline adapters, validators, and processors reusable across sources. A CSV reader and a database cursor both need `.read()` or `.fetch()` methods; a protocol captures this contract independently of implementation.

## Practice

**Problem:** You're building a data loader that accepts multiple source types (API client, CSV file handle, database connection). Each has different methods and attributes, but all must provide a way to fetch rows and return metadata (source name, record count). Write a type-safe loader without depending on concrete source classes.

```python
from typing import Protocol, runtime_checkable
from typing import Any, Iterator

@runtime_checkable
class DataSource(Protocol):
    """Structural contract for any data source in the pipeline."""
    
    def fetch_rows(self) -> Iterator[dict[str, Any]]:
        """Yield rows as dictionaries."""
        ...
    
    def metadata(self) -> dict[str, str | int]:
        """Return {source_name: str, record_count: int}."""
        ...

def load_job_postings(source: DataSource) -> list[dict]:
    """Accept any object with fetch_rows() and metadata()."""
    meta = source.metadata()
    rows = list(source.fetch_rows())
    
    # Type checker confirms source has these methods
    print(f"Loaded {meta['record_count']} rows from {meta['source_name']}")
    return rows

# Different concrete implementations, no shared base class
class APIJobSource:
    def fetch_rows(self):
        return iter([{"job_id": 1, "job_title_short": "DE"}])
    def metadata(self):
        return {"source_name": "LinkedIn API", "record_count": 1}

class CSVJobSource:
    def fetch_rows(self):
        return iter([{"job_id": 2, "job_title_short": "DA"}])
    def metadata(self):
        return {"source_name": "jobs.csv", "record_count": 1}

# Both work with load_job_postings() without modification
load_job_postings(APIJobSource())
load_job_postings(CSVJobSource())
```

## Notes

- **@runtime_checkable** is essential for protocols you validate at runtime (e.g., `isinstance(obj, DataSource)`); omitting it makes the protocol only visible to static type checkers.
- Protocols are most powerful in layered pipelines: validators accept `Validator` protocols, transformers accept `Transformer` protocols, sinks accept `Sink` protocols—each layer stays loosely coupled.
- Distinguish protocols from abstract base classes: protocols are structural, ABCs are nominal. ABCs still have a place when you own the hierarchy; protocols win when integrating external code.
- Common mistake: defining a protocol but not making it `@runtime_checkable`, then using `isinstance()` checks—the runtime will raise an error. Always check what validation you actually need.
- Revisit: **Generics with protocols** (e.g., `DataSource[T]`) for type-safe row schemas, and **PEP 544 (protocols)** spec for advanced features like `@overload` and variance.
