---
date: 2026-10-25
phase: python
topic: Mutable default arguments and common pitfalls
---

# Mutable default arguments and common pitfalls

*Python for data engineering*

## Concept

Mutable default arguments in Python (lists, dicts, sets) are evaluated **once at function definition time**, not each time the function is called. This means all invocations share the same underlying object, leading to unexpected state mutations across calls. In data pipelines, this is dangerous: a transform function that appends to a default list parameter will accumulate results across pipeline stages, corrupting downstream data.

The issue matters most when building reusable pipeline components—validators, aggregators, or ETL step functions—that are called repeatedly. Without awareness, a simple function like `def filter_jobs(records, excluded_ids=[])` will retain excluded IDs from previous calls, silently filtering records that should have passed through.

The fix is mechanical: use immutable defaults (`None`) and initialize mutable objects inside the function body. This forces each call to create its own state, ensuring functions remain composable and testable.

## Practice

**Problem:** You're building a data validation step for job postings. The validator should reject records with missing required fields. A junior engineer writes:

```python
def validate_job_posting(record, required_fields=["job_id", "job_title_short"]):
    missing = []
    for field in required_fields:
        if field not in record or record[field] is None:
            missing.append(field)
    return len(missing) == 0, missing
```

After the first call with incomplete data, subsequent calls with *complete* records still report the same fields as missing. The `missing` list is local, but `required_fields` is shared across calls. If another stage mutates `required_fields`, validation rules drift silently.

**Solution:**

```python
def validate_job_posting(record, required_fields=None):
    """Validate job posting has all required fields.
    
    Args:
        record: dict with job posting data
        required_fields: list of field names; defaults to standard schema
    
    Returns:
        (is_valid: bool, missing_fields: list)
    """
    if required_fields is None:
        required_fields = ["job_id", "job_title_short", "salary_year_avg"]
    
    missing = []
    for field in required_fields:
        if field not in record or record[field] is None:
            missing.append(field)
    
    return len(missing) == 0, missing
```

Now each call gets its own `missing` list and uses a fresh default list if none is provided.

## Notes

- **Mutable defaults persist across module reloads** in notebooks and long-running processes; always use `None` as the sentinel for optional mutable arguments.
- **Type hints expose the antipattern:** `def f(x: list = [])` is a code smell; properly typed it should be `x: list | None = None`.
- **Connect to:** defensive copying (`copy.deepcopy`), immutable data structures (tuples, frozensets), and the principle of pure functions in functional data pipelines.
- **Testing catches this:** unit tests that call the same function twice with different inputs will fail if mutable defaults are used, making the bug obvious during CI.
- **Revisit:** generator functions and comprehensions handle this differently (they create fresh scopes); list/dict comprehensions avoid the trap entirely.
