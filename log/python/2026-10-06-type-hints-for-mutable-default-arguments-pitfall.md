---
date: 2026-10-06
phase: python
topic: Type hints for mutable default arguments pitfall
---

# Type hints for mutable default arguments pitfall

*Python for data engineering*

## Concept

In Python, mutable default arguments (lists, dicts, sets) are created once when the function is defined, not each time it's called. This means all function invocations share the same object in memory. A data pipeline that uses mutable defaults—especially in extractors, transformers, or loaders—will silently accumulate state across calls, corrupting data and making bugs nearly impossible to trace.

Type hints alone don't prevent this problem, but they signal intent: `list[dict]` vs `list[dict] | None` forces you to be explicit about whether you're accepting an optional collection. When combined with runtime checks and the immutable-default pattern, type hints document what should happen.

Without fixing this, a function like `def parse_records(data, accumulated=[])` will grow the `accumulated` list across every call in your pipeline, potentially combining records from different jobs, batches, or runs into a single corrupted result.

## Practice

**Problem:** A data validation function that logs invalid job postings should reset its log for each batch, but instead accumulates all failures across multiple pipeline runs.

```python
# ❌ WRONG: mutable default
def validate_job_postings(
    records: list[dict],
    invalid_log: list[dict] = []
) -> tuple[list[dict], list[dict]]:
    for record in records:
        if not record.get('job_id'):
            invalid_log.append(record)
    return records, invalid_log

# ✅ CORRECT: immutable default + type hints
def validate_job_postings(
    records: list[dict],
    invalid_log: list[dict] | None = None
) -> tuple[list[dict], list[dict]]:
    if invalid_log is None:
        invalid_log = []
    for record in records:
        if not record.get('job_id'):
            invalid_log.append(record)
    return records, invalid_log
```

## Notes

- **Mutable defaults are evaluated at *definition* time, not call time.** Print the object's `id()` before and after calls to verify they're the same object across invocations.
- **Type hints with `| None` create a visual contract:** readers immediately see "this parameter might not be provided, so check for None." This is clearer than `list = []` which hides the trap.
- **Use linters and type checkers:** `pylint --disable=dangerous-default-value` or enable it; `mypy` doesn't catch this but documenting the pattern prevents it.
- **Connects to dependency injection:** passing state explicitly (even as `None` defaults) makes functions pure and testable; extract/transform/load stages should never rely on hidden module-level state.
- **Revisit when testing:** unit tests will expose mutable-default bugs fast if you run the same function twice; integration tests may miss them if each run is isolated.
