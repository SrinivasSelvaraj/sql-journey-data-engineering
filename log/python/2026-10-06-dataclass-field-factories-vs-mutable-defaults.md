---
date: 2026-10-06
phase: python
topic: Dataclass field factories vs mutable defaults
---

# Dataclass field factories vs mutable defaults

*Python for data engineering*

## Concept

In Python dataclasses, mutable default values (lists, dicts, sets) are shared across all instances unless you use `field(default_factory=...)`. This happens because the default is evaluated once at class definition time, not per instance. In data pipelines, this causes silent data corruption: two pipeline runs or batch records accidentally share the same list, leading to duplicate entries, lost data, or mysterious bugs that are hard to trace.

The fix is `field(default_factory=list)` or `field(default_factory=dict)`, which calls the factory function for each new instance. This is essential when building ETL stages where dataclass instances represent rows, batches, or job configs. Without it, appending to what you think is "this record's tags" actually appends to every record's tags.

The pattern matters most in data engineering because pipelines process thousands or millions of records in loops. A mutable default bug won't show up in unit tests with one or two objects—it emerges in production when batch size hits 100+. Typed dataclasses with proper factories are how you avoid this class of bug entirely.

## Practice

**Problem:** You are building a fact table loader. The `job_postings_fact` schema includes a job_location field that can have multiple cities (denormalized into a list for analytics). You write a dataclass to represent staging rows, give `job_locations` a default empty list, and loop through CSV records. By record 500, all jobs show the same location list from record 1.

**Solution:**

```python
from dataclasses import dataclass, field
from datetime import date
from typing import List

@dataclass
class JobPostingFact:
    job_id: int
    job_title_short: str
    salary_year_avg: float
    job_work_from_home: bool
    job_posted_date: date
    job_locations: List[str] = field(default_factory=list)  # ✓ Factory, not []

# Safe usage in pipeline:
jobs = []
for row in csv_reader:
    job = JobPostingFact(
        job_id=row['job_id'],
        job_title_short=row['job_title'],
        salary_year_avg=float(row['salary']),
        job_work_from_home=row['remote'] == 'TRUE',
        job_posted_date=date.fromisoformat(row['posted_date'])
    )
    job.job_locations.append(row['location'])  # Each instance gets its own list
    jobs.append(job)
```

## Notes

- **Mutable default trap:** `job_locations: List[str] = []` creates one list object shared across all instances. Always use `field(default_factory=...)` for list, dict, set, or any custom mutable type.
- **Type hints + dataclasses = safety:** Declaring `List[str]` and using `field(default_factory=list)` together catches both the runtime bug and signals intent to readers and linters.
- **Testing catches it:** This bug is invisible in unit tests with 1–2 instances. Always test dataclass defaults with a loop of 10+ objects to surface sharing issues early.
- **Relates to:** copy vs deepcopy semantics, how Python evaluates default arguments in regular functions (same footgun), and immutable data structures for audit trails in data pipelines.
- **Revisit when:** adding optional configs to pipeline job classes, building domain models for fact/dimension tables, or debugging "ghost data" in batch operations.
