---
date: 2026-09-14
phase: python
topic: __dunder__ methods: hash, eq, lt for custom types
---

# __dunder__ methods: hash, eq, lt for custom types

*Python for data engineering*

## Concept

Dunder methods like `__hash__`, `__eq__`, and `__lt__` define how Python objects behave in collections, comparisons, and sorting—critical when building custom data types for pipelines. Without them, you can't reliably deduplicate records in sets, compare salary ranges in sorting logic, or use objects as dictionary keys. In data engineering, this matters immediately: you might load Job objects into a set to remove duplicates, sort them by salary, or join them by equality—all of which silently fail or behave unexpectedly if these methods aren't implemented.

The default behavior uses object identity (memory address), not data values. Two Job objects with identical `job_id` and `salary_year_avg` are treated as different because they're different objects in memory. Without `__eq__`, `set([job1, job2])` keeps both even if they're duplicates; without `__lt__`, sorting by salary requires verbose lambda functions; without `__hash__`, you can't use the object as a dictionary key or in a set at all.

In production pipelines, this causes silent data loss (duplicates leak through), incorrect ordering (salary comparisons fail), and pipeline crashes (unhashable type errors when deduplicating). Implementing these methods makes your types behave like built-in types—predictable and composable with Python's standard tools.

## Practice

**Problem:** You're loading job postings into memory and need to:
1. Deduplicate by `job_id` using a set
2. Sort by `salary_year_avg` (descending)
3. Use a dict to map `job_id` → Job object for joins

Without `__hash__` and `__eq__`, deduplication fails; without `__lt__`, sorting requires manual lambdas.

```python
from dataclasses import dataclass
from datetime import date

@dataclass(frozen=True)  # Immutable; required for hashability
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: int
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    def __hash__(self):
        return hash((self.job_id, self.job_title_short))
    
    def __eq__(self, other):
        if not isinstance(other, JobPosting):
            return False
        return self.job_id == other.job_id and self.job_title_short == other.job_title_short
    
    def __lt__(self, other):
        # Sort by salary descending (negate for reverse)
        if not isinstance(other, JobPosting):
            return NotImplemented
        return self.salary_year_avg > other.salary_year_avg

# Usage
jobs = [
    JobPosting(1, "Data Engineer", 120000, True, date(2024, 1, 15), "Remote"),
    JobPosting(2, "Data Engineer", 115000, False, date(2024, 1, 16), "NYC"),
    JobPosting(1, "Data Engineer", 120000, True, date(2024, 1, 15), "Remote"),  # Duplicate
]

# Deduplication via set
unique_jobs = set(jobs)  # Now works; uses __hash__ and __eq__
assert len(unique_jobs) == 2

# Sorting by salary
sorted_jobs = sorted(jobs, key=lambda j: j.salary_year_avg, reverse=True)
# Or rely on __lt__:
sorted_jobs = sorted(set(jobs))  # Uses __lt__ for comparison

# Use as dict key
job_map = {job.job_id: job for job in unique_jobs}  # Uses __hash__
```

## Notes

- **Dataclass shortcut**: Use `@dataclass(frozen=True)` to auto-generate `__hash__` and `__eq__` based on fields; manually override only when dedup logic differs from field-by-field equality.
- **Hash consistency**: If you override `__eq__`, override `__hash__` too; if two objects are equal, they must have the same hash. Violating this breaks sets and dicts silently.
- **Immutability requirement**: Objects in sets and dict keys must be immutable (or at least not mutate their hash-relevant fields after insertion), or lookups fail. `frozen=True` enforces this.
- **`__lt__` vs `__le__`, `__gt__`, etc.**: Implement only `__lt__` and `__eq__`; Python's `functools.total_ordering` decorator auto-generates the rest—cleaner than writing all six comparison methods.
- **Adjacent topics**: Understand `collections.namedtuple` (lightweight immutable alternative), `typing.NamedTuple` (typed version), and how `__repr__` aids debugging of custom objects in logs.
