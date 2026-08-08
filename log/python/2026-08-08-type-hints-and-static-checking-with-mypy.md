---
date: 2026-08-08
phase: python
topic: Type hints and static checking with mypy
---

# Type hints and static checking with mypy

*Python for data engineering*

## Concept

Type hints annotate function parameters and return values with expected data types, making code intention explicit and enabling static analysis tools like mypy to catch bugs before runtime. In data pipelines, where data flows through multiple transformation stages and schemas evolve, type hints act as executable documentation and guardrails—they prevent silent type mismatches that corrupt downstream data. Without them, a function accepting `salary_year_avg: int` might receive a string from a CSV parse, silently fail comparison operations, or propagate bad data through your entire pipeline before anyone notices.

Mypy performs static type checking by analyzing your code without executing it, catching type incompatibilities at development time rather than in production. This is especially critical in data engineering, where bugs often hide in infrequently-executed conditional branches or edge cases (null salaries, missing dates). Type hints also serve as inline contracts—when you see `def filter_jobs(postings: list[dict]) -> list[dict]`, you immediately know the function's shape without reading its body.

## Practice

**Problem:** You receive job posting data from a CSV with inconsistent types—some salary values are strings, some are None, and some are already parsed integers. Your filter function needs to handle this safely and return only valid records. Without type hints, downstream aggregations silently fail or compute wrong results.

```python
from typing import Optional
from datetime import date

def filter_valid_postings(
    postings: list[dict],
    min_salary: int
) -> list[dict]:
    """Filter job postings with valid salary and location."""
    valid = []
    for posting in postings:
        # Type hints make it clear: salary_year_avg could be None
        salary = posting.get('salary_year_avg')
        
        # Explicit handling catches the type mismatch early
        if salary is None:
            continue
        
        # Mypy ensures you convert before comparison
        try:
            salary_int = int(salary) if isinstance(salary, str) else salary
        except (ValueError, TypeError):
            continue
        
        if salary_int >= min_salary:
            valid.append(posting)
    
    return valid
```

Annotate the return type and add input validation; mypy will flag if callers pass wrong types or ignore the Optional return.

## Notes

- **Mypy strictness levels:** Start with `--strict` flag; it catches missing return types, unannotated function parameters, and Optional misuse that lenient checking misses.
- **Union and Optional are your friends:** Use `salary: Optional[int]` (or `int | None` in Python 3.10+) to document that a field might be missing; mypy forces you to handle both branches.
- **Type hints integrate with IDEs:** Modern editors use type information for autocomplete and inline error reporting—better DX, fewer bugs caught later.
- **Common mistake—over-generalization:** Annotating everything as `Any` defeats the purpose; be specific (`list[dict[str, int]]` beats `list`).
- **Connect to validation frameworks:** Pydantic or dataclasses + mypy combine to enforce schemas end-to-end; consider them for structured data pipelines.
