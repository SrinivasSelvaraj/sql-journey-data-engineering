---
date: 2026-10-06
phase: python
topic: Import cycles and module initialization order
---

# Import cycles and module initialization order

*Python for data engineering*

## Concept

Import cycles occur when module A imports from module B, which imports from module A (directly or through a chain). Python tries to execute both modules simultaneously, causing one to encounter names that haven't been defined yet. In data pipelines, this is particularly dangerous because initialization order determines whether your ETL configs, database connections, and logging setup are ready before the first transform runs.

The problem surfaces most in medium-sized projects: a `pipeline.py` imports a transform function from `transforms.py`, which imports a logger or config object from `pipeline.py`. When you run the pipeline, Python gets partway through loading each module, hits an undefined name, and raises `ImportError` or `AttributeError`. Without careful attention to module initialization, your pipeline fails at import time before any actual data work begins.

Prevention requires understanding that Python executes module code top-to-bottom exactly once per process. Defer imports to function scope (inside functions, not at module level), separate configuration/initialization from business logic, and be explicit about what each module owns. This is a form of dependency injection—making what a module needs an argument or explicit parameter, not a hidden import.

## Practice

**Problem:** You have a data pipeline that loads job posting facts. Your `etl/transforms.py` validates and cleans salary data using a regex pattern stored in `etl/config.py`. Meanwhile, `etl/config.py` imports a transform function to test the regex at startup. This creates a cycle: `transforms` → `config` → `transforms`.

**Solution:** Move the regex pattern into a dedicated constants module with no imports, or move the validation function into `config.py` itself:

```python
# etl/constants.py (zero imports of other etl modules)
SALARY_PATTERN = r'^\$?[\d,]+(?:\.\d{2})?$'

# etl/transforms.py
import re
from etl.constants import SALARY_PATTERN

def validate_salary(value: str) -> bool:
    return bool(re.match(SALARY_PATTERN, value))

def clean_job_posting(row: dict) -> dict:
    if not validate_salary(row['salary_year_avg']):
        row['salary_year_avg'] = None
    return row

# etl/pipeline.py (imports only from transforms and constants)
from etl.transforms import clean_job_posting
from etl.constants import SALARY_PATTERN
```

## Notes

- **Symptom detection:** If you see `ImportError: cannot import name 'X' from partially initialized module 'Y'`, you have a cycle. Add `print()` statements at module level to see execution order.
- **Lazy imports:** Move `from module import thing` inside function definitions to delay resolution until runtime; only do this when the module is expensive to load or part of a cycle.
- **Testing connection:** Circular imports make unit testing harder because you can't isolate modules. Separating config/constants from logic forces you to write injectable, testable functions.
- **Related patterns:** This overlaps with dependency injection (pass dependencies as arguments), the single-responsibility principle (each module has one job), and factory patterns (create objects in dedicated modules).
- **Revisit when:** Refactoring a large pipeline or adding new data sources; cycles often hide poor module boundaries that become painful later.
