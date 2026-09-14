---
date: 2026-09-14
phase: python
topic: Closures and late binding in loops
---

# Closures and late binding in loops

*Python for data engineering*

## Concept

A **closure** captures variables from an enclosing scope; **late binding** means that closure reads the *current* value of a variable when the closure executes, not when it was defined. In loops, this creates a trap: if you create multiple functions in a loop without capturing the loop variable explicitly, all closures reference the same variable—and by the time any function runs, the loop has finished and the variable holds its final value.

This matters in data pipelines when you build lists of validators, transformers, or error handlers dynamically. Without understanding late binding, all your validators might check the same column, or all your filters might use the same threshold, even though you intended each to work on different inputs.

Without fixing this, a pipeline that validates five CSV columns will pass or fail all five based on whichever column was last in the loop. Similarly, a set of partition pruning functions might all prune by the same date range.

## Practice

**Problem:** Write a SQL query that creates five separate validators—one for each of these columns: `job_id`, `job_title_short`, `salary_year_avg`, `job_work_from_home`, `job_posted_date`. Each validator should check if that column contains nulls. In Python pseudocode, show how late binding breaks this, then fix it.

**Broken approach (late binding trap):**
```python
validators = []
columns = ['job_id', 'job_title_short', 'salary_year_avg', 'job_work_from_home', 'job_posted_date']
for col in columns:
    validators.append(lambda row: row[col] is not None)

# All five lambdas check 'job_posted_date' (the last value of col)
```

**Fixed approach (capture with default argument):**
```python
validators = []
columns = ['job_id', 'job_title_short', 'salary_year_avg', 'job_work_from_home', 'job_posted_date']
for col in columns:
    validators.append(lambda row, col=col: row[col] is not None)

# Each lambda now captures its own col value at definition time
# Equivalent SQL: WHERE job_id IS NOT NULL AND job_title_short IS NOT NULL ...
```

## Notes

- **Default argument captures at definition time**, mutable objects do not—use immutable defaults (strings, numbers, tuples) for loop variables.
- **List comprehensions avoid this entirely**: `[lambda row, c=col: row[c] is not None for col in columns]` is safer and clearer than a loop.
- **Factory functions are explicit**: `def make_validator(col): return lambda row: row[col] is not None` makes intent obvious and survives code review better.
- **Type hints expose the risk**: if you annotate `validators: list[Callable[[dict], bool]]`, you're forced to think about what each closure closes over.
- **Connects to**: decorator patterns, partial functions, functools.partial as an alternative to lambdas, and testing pipeline stage composition.
