---
date: 2026-09-14
phase: python
topic: Descriptors and property getters with side effects
---

# Descriptors and property getters with side effects

*Python for data engineering*

## Concept

Descriptors and property getters with side effects create hidden dependencies in data pipelines that are difficult to test and debug. A property getter should be a pure function—calling it multiple times with the same object state should produce identical results—but side effects (logging, caching, database queries, file writes) violate this principle. In data engineering, this matters because a pipeline step that looks simple (`employee.salary`) might silently trigger a database round-trip or cache invalidation, making performance unpredictable and test assertions fragile. Without discipline here, you end up with pipeline code that works locally but fails under load, or tests that pass in isolation but fail when run together.

The danger compounds in ETL workflows where you iterate over millions of records. A property that performs I/O on every access becomes a performance cliff; one that mutates internal state or external systems becomes non-idempotent, breaking recovery and retry logic. Type hints mask the problem—`@property def salary(self) -> float:` looks like a cheap attribute access but might query a remote API. Testability suffers because you cannot mock or assert on side effects without intrusive instrumentation.

## Practice

**Problem:** Your fact table loads job postings, and you need to enrich `job_location` by geocoding coordinates from a slow external API. A naive approach uses a property getter that calls the API on every access.

**Broken approach:** Property makes side effects invisible
```python
class JobPosting:
    def __init__(self, job_id: int, location_name: str):
        self.job_id = job_id
        self._location_name = location_name
        self._coords = None
    
    @property
    def coordinates(self) -> tuple[float, float]:
        # Side effect hidden; called every access or cached unpredictably
        if self._coords is None:
            self._coords = geocode_api(self._location_name)  # I/O!
        return self._coords
```

**Solution:** Explicit, testable enrichment step
```sql
-- Batch geocoding in SQL before fact table load
WITH raw_postings AS (
  SELECT job_id, job_title_short, salary_year_avg, 
         job_work_from_home, job_posted_date, job_location
  FROM staging.job_postings_raw
),
geocoded AS (
  SELECT 
    rp.*,
    CASE 
      WHEN g.latitude IS NOT NULL THEN ST_Point(g.longitude, g.latitude)
      ELSE NULL 
    END AS job_location_coords
  FROM raw_postings rp
  LEFT JOIN reference.location_geocodes g 
    ON UPPER(rp.job_location) = UPPER(g.location_name)
)
INSERT INTO fact.job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, 
   job_posted_date, job_location, job_location_coords)
SELECT * FROM geocoded;
```

Python alternative: explicit method, no side effects in properties
```python
def enrich_job_postings(postings: list[dict]) -> list[dict]:
    """Geocode locations in batch; side effect is explicit and testable."""
    locations = {p["job_location"] for p in postings}
    geocodes = batch_geocode_api(locations)  # One call, not millions
    
    for p in postings:
        p["coordinates"] = geocodes.get(p["job_location"])
    return postings
```

## Notes

- **Avoid `@property` for I/O:** Use explicit methods (`get_coordinates()`) or batch operations. Properties should be cheap and pure; if you need to document "calling this makes a database query," you've lost the abstraction.
- **Batch over row-by-row:** Geocoding 1M locations one at a time via property access is a DoS on your API and test suite. Load reference data once, join in SQL, or batch-fetch in Python before iteration.
- **Immutability in pipelines:** Once a fact row is enriched, it should be immutable. Setters with side effects (e.g., `@location.setter` that logs to a queue) hide state mutations; use pure functions and explicit event emission instead.
- **Test observability:** If enrichment *must* happen in Python, separate data transformation from I/O. Pass a mock geocoder to the enrichment function; assert on output, not on whether an API was called.
- **Related:** Lazy evaluation in Spark/Pandas uses similar patterns—be explicit about when operations trigger computation. Caching strategies (Redis, in-process) also hide side effects; prefer explicit cache layers with clear TTLs.
