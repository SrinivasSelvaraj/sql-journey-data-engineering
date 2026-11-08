---
date: 2026-11-08
phase: python
topic: Type hints: generic types, TypeVar and Protocol definitions
---

# Type hints: generic types, TypeVar and Protocol definitions

*Python for data engineering*

## Concept

Type hints in Python allow you to declare expected input and output types for functions and classes, making code self-documenting and enabling static type checkers like `mypy` to catch bugs before runtime. Generic types (e.g., `List[str]`, `Dict[str, int]`) specify the container *and* its contents; `TypeVar` lets you write reusable functions that preserve type information across calls (e.g., a function that takes and returns the same type); `Protocol` defines a structural interface without inheritance, letting any object that "quacks like a duck" satisfy the contract.

In data pipelines, type hints become critical because bad input propagates silently—a string passed where an integer is expected might succeed at first but fail downstream in an aggregation or join. Without hints, you only discover these breaks during integration testing or in production. Typed code is also more testable: type checkers validate your test fixtures match real schemas, and IDEs can auto-complete columns and methods, reducing typos in long data transformations.

`TypeVar` and `Protocol` solve the problem of writing generic pipeline utilities: a function that reads CSV, parses JSON, or validates row schemas should work for *any* compatible input type without rewriting the logic. Protocols especially help when you depend on behavior (a logger, a database cursor, a data frame-like object) rather than a concrete class—your pipeline stays flexible and mockable.

## Practice

**Problem:** Write a generic function that extracts salary statistics from any iterable of job posting records. The function should accept records with a `salary_year_avg` field, filter out `None` values, and return a tuple of (mean, max, min). It should work with dictionaries, dataclass instances, or custom record types without rewriting the logic.

```python
from typing import TypeVar, Protocol, Iterable, Tuple, Optional, runtime_checkable

@runtime_checkable
class HasSalary(Protocol):
    """Any object with a salary_year_avg attribute (int or None)."""
    salary_year_avg: Optional[int]

T = TypeVar('T', bound=HasSalary)

def compute_salary_stats(records: Iterable[T]) -> Tuple[float, int, int]:
    """Extract salary statistics from job postings.
    
    Args:
        records: Iterable of objects with salary_year_avg field.
        
    Returns:
        Tuple of (mean_salary, max_salary, min_salary).
        Raises ValueError if no valid salaries found.
    """
    salaries = [
        r.salary_year_avg 
        for r in records 
        if r.salary_year_avg is not None
    ]
    if not salaries:
        raise ValueError("No valid salary data found")
    
    return (sum(salaries) / len(salaries), max(salaries), min(salaries))

# Works with dicts (when using SimpleNamespace wrapper)
from types import SimpleNamespace
jobs_dict = [
    SimpleNamespace(salary_year_avg=95000),
    SimpleNamespace(salary_year_avg=None),
    SimpleNamespace(salary_year_avg=120000),
]
mean, max_sal, min_sal = compute_salary_stats(jobs_dict)
# mypy confirms types; function is testable with any record shape
```

## Notes

- **Common mistake:** using `List[Any]` or untyped function parameters; this defeats the purpose and makes refactoring dangerous in pipelines where column names or record structure changes.
- **Bound TypeVar vs. Protocol:** `TypeVar('T', bound=MyClass)` enforces inheritance; `Protocol` is looser and doesn't require explicit subclassing, making it ideal for polymorphic pipelines.
- **Runtime checking:** add `@runtime_checkable` to `Protocol` if you need `isinstance()` checks at runtime (e.g., validating ETL input before processing).
- **Adjacent topics:** dataclasses and NamedTuple pair naturally with generics; Pydantic models use `Generic` for schema-agnostic validators; `typing.cast()` is a last resort when the type checker can't infer but you're confident.
- **Revisit:** the difference between `Iterable`, `Iterator`, and `Generator`; variance (covariance/contravariance) when nesting generics; using `overload` for functions with multiple valid type signatures.
