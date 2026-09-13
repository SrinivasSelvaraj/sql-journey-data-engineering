---
date: 2026-09-13
phase: python
topic: functools.lru_cache and cache invalidation patterns
---

# functools.lru_cache and cache invalidation patterns

*Python for data engineering*

## Concept

`functools.lru_cache` is a decorator that memoizes function results based on input arguments, storing up to a maximum number of recent calls. In data pipelines, this prevents redundant transformations, API calls, or database queries when the same input appears multiple times—common in ETL when processing denormalized fact tables or handling late-arriving dimensions. Without explicit cache invalidation, stale results flow downstream, corrupting aggregations and breaking incremental loads; with it, you trade memory for speed but must design for cache lifetime and freshness guarantees.

The decorator is thread-safe in CPython but not process-safe, matters when using multiprocessing, and the `maxsize` parameter is critical—too small and you thrash the cache; too large and you leak memory on long-running jobs. Cache invalidation becomes the real problem: caches are only safe when the underlying data is truly immutable or when you explicitly clear them at logical boundaries (per batch, per day, per source partition).

## Practice

**Problem:** Your pipeline loads job postings hourly. A lookup function maps `job_id` to denormalized `job_title_short` and `job_work_from_home` flag by joining against a slow reference table. The same job_id appears thousands of times per batch (duplicated postings across locations). Without caching, you query the reference table 10,000 times; with naive caching across batches, you miss job title updates posted in the latest hour.

```python
from functools import lru_cache
from datetime import datetime, timedelta
from typing import NamedTuple

class JobRef(NamedTuple):
    job_title_short: str
    job_work_from_home: bool

class JobLookup:
    def __init__(self, db_conn, batch_hour: datetime):
        self.db = db_conn
        self.batch_hour = batch_hour
        self._cache_start = batch_hour
    
    @lru_cache(maxsize=5000)
    def get_job_ref(self, job_id: int) -> JobRef:
        """Cached within a single batch hour only."""
        query = """
        SELECT job_title_short, job_work_from_home 
        FROM job_reference 
        WHERE job_id = %s
        """
        result = self.db.fetchone(query, (job_id,))
        if not result:
            raise ValueError(f"job_id {job_id} not found")
        return JobRef(*result)
    
    def invalidate_cache(self):
        """Call at batch boundary to clear stale entries."""
        self.get_job_ref.cache_clear()

# Usage in pipeline
lookup = JobLookup(db, batch_hour=datetime(2024, 1, 15, 14, 0))
for row in job_postings_batch:
    ref = lookup.get_job_ref(row['job_id'])
    # ...transform and load...

lookup.invalidate_cache()  # Before next batch hour
```

## Notes

- **Cache as a footgun:** `lru_cache` silently returns stale results; wrap it with explicit lifecycle management (batch scope, TTL decorator) rather than relying on size eviction alone.
- **Maxsize tuning is empirical:** use `cache_info()` to inspect hit ratio and eviction rate; aim for >80% hit rate without exceeding available memory on your executor nodes.
- **Thread-safety ≠ process-safety:** in Spark or multiprocessing contexts, each worker gets its own cache—sometimes desired (isolation), sometimes wasteful (no sharing); consider shared state (Redis, DuckDB temp tables) for cross-process caching.
- **Adjacent patterns:** partial function application, decorator composition, and context managers all pair well; also intersects with Pydantic model caching and SQLAlchemy query result caching.
- **Revisit:** cache busting strategies (versioning inputs, time-based TTL, explicit invalidation signals from upstream), and when *not* to cache (small lookups, rare duplicates, non-deterministic functions).
