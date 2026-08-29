---
date: 2026-08-29
phase: python
topic: Memory leaks: reference cycles and weak references
---

# Memory leaks: reference cycles and weak references

*Python for data engineering*

## Concept

Memory leaks occur when objects remain in memory even after they're no longer needed, preventing garbage collection. In Python, the most common cause is **reference cycles**—when two or more objects reference each other, creating a loop that the garbage collector may not break immediately (especially in older code or C extensions). This matters in data pipelines because long-running processes accumulate leaked memory, causing performance degradation, pipeline crashes, and unpredictable behavior in production.

**Weak references** solve this by allowing an object to reference another without preventing garbage collection. When you use `weakref.ref()` or `weakref.proxy()`, the reference doesn't count toward the reference count, so if no strong references remain elsewhere, the object can be freed. This is essential when building data structures (like caches, event handlers, or observer patterns) where circular dependencies are natural but shouldn't keep objects alive indefinitely.

Without addressing cycles and weak references, pipelines leak memory through handler registrations, cached DataFrames held in bidirectional relationships, or Spark driver memory consumed by lingering object graphs. In ETL contexts, this directly impacts batch window sizes and forces restarts that hurt SLA compliance.

## Practice

**Problem:** A job posting cache holds references to both `Job` objects and their `Employer` objects. Each `Employer` maintains a list of associated `Job` objects for quick lookup. This creates a cycle: `Job → Employer → [Job, ...]`. Over time, cached jobs are removed from the pipeline but never garbage-collected because the employer still holds strong references.

```python
import weakref
from typing import List, Optional

class Employer:
    def __init__(self, employer_id: int, company_name: str):
        self.employer_id = employer_id
        self.company_name = company_name
        self.jobs: List[weakref.ref] = []  # Store weak references only
    
    def add_job(self, job: 'Job') -> None:
        self.jobs.append(weakref.ref(job))
    
    def get_active_jobs(self) -> List['Job']:
        # Filter out garbage-collected jobs (dead weak refs)
        return [job() for job in self.jobs if job() is not None]

class Job:
    def __init__(self, job_id: int, title: str, employer: Employer):
        self.job_id = job_id
        self.title = title
        self.employer = employer  # Strong reference is fine here
        employer.add_job(self)     # Employer holds only weak ref back

# Cache can now safely discard jobs without blocking GC
job_cache = {}
employer = Employer(42, 'Acme Corp')
job = Job(1, 'Data Engineer', employer)
job_cache[1] = job

del job  # Removes the only strong reference
# Job is now garbage-collected; employer.get_active_jobs() will not include it
```

## Notes

- **Bidirectional relationships are the trap:** Parent→child + child→parent is a cycle. Use weak references on the "back pointer" (typically child→parent) to break it.
- **Weak refs return `None` when dereferenced:** Always check `if obj() is not None` before using weak references; they can vanish between checks if no other references exist.
- **Garbage collection isn't instant:** Python's GC may not run immediately on reference count drop, especially with cycles. Use `gc.collect()` sparingly in tests or debug suspicious leaks, but don't rely on it in production.
- **Context managers + `__del__` are risky:** Avoid implementing `__del__` if you're unsure about reference graphs; context managers (`with` statements) are far safer for cleanup in pipelines.
- **Connects to:** object pooling (preventing allocation churn), context managers (deterministic cleanup), and profiling tools like `tracemalloc` and `memory_profiler` for detecting actual leaks in long-running jobs.
