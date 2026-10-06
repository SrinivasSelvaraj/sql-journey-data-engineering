---
date: 2026-10-06
phase: python
topic: Memory leaks: circular references and gc module
---

# Memory leaks: circular references and gc module

*Python for data engineering*

## Concept

A **circular reference** occurs when two or more objects reference each other, creating a cycle that prevents Python's reference counter from deallocating them even after they're no longer needed. In CPython, the reference counter alone cannot break cycles; the `gc` (garbage collector) module uses cycle detection to find and remove these orphaned object graphs. This matters in data pipelines when ETL classes hold references to each other (e.g., a `DataSource` linked to a `Pipeline` linked back to `DataSource`), or when callbacks capture context objects that capture callbacks. Without active garbage collection, long-running pipelines leak memory incrementally—especially problematic when processing millions of records in loops, where temporary objects accumulate.

The `gc` module provides `gc.collect()` to force cycle detection and `gc.set_debug(gc.DEBUG_SAVEALL)` to inspect what gets collected. Disabling garbage collection with `gc.disable()` trades memory for speed in tight loops (common in data processing), but risks leaks if cycles form. For data engineering, the practical concern is distinguishing between acceptable growth (buffering data in memory during batch processing) and true leaks (holding references to exhausted generators, old connections, or cached results).

## Practice

**Problem:** A data pipeline class holds a reference to its logger, which is also registered as a listener in a central event dispatcher. The dispatcher keeps a reference to all listeners. When the pipeline finishes, the pipeline object is deleted, but the logger remains in the dispatcher's list, and the dispatcher remains referenced by the module. The pipeline and logger form a cycle through the dispatcher, preventing memory cleanup between job runs.

```python
import gc

class JobProcessor:
    def __init__(self, job_id, logger):
        self.job_id = job_id
        self.logger = logger
        self.logger.listeners.append(self)  # circular: logger → processor → logger
    
    def process(self):
        pass

# Solution: explicit cleanup and cycle detection
def run_pipeline():
    processor = JobProcessor(123, shared_logger)
    processor.process()
    del processor  # delete reference
    gc.collect()  # force collection of circular references

# Or use context manager for guaranteed cleanup
class JobProcessor:
    def __enter__(self):
        return self
    
    def __exit__(self, *args):
        self.logger.listeners.remove(self)  # break cycle explicitly
        gc.collect()  # optional; __exit__ alone often suffices

# Usage in pipeline
with JobProcessor(123, shared_logger) as processor:
    processor.process()
# Cycle broken automatically on exit
```

## Notes

- **Don't disable `gc` by default**: `gc.disable()` speeds up tight loops but defers all cycle collection to manual calls—use only in profiled hot paths, then re-enable.
- **Weak references** (`weakref` module) break cycles elegantly: use them for backreferences (e.g., child→parent) instead of strong references.
- **Context managers (`__enter__`/`__exit__`) prevent more leaks than garbage collection fixes**—they remove the cycle before it forms, not after.
- **Inspect leaks with `gc.get_objects()`** and `gc.DEBUG_SAVEALL` during testing; in production, monitor RSS/memory growth over multiple pipeline runs.
- **Adjacent topics**: connection pooling (hold/release patterns), generator cleanup (use `try`/`finally`), and profiling tools like `memory_profiler` that reveal accumulation across pipeline batches.
