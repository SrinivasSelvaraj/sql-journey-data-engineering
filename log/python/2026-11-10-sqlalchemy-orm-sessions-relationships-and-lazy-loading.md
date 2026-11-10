---
date: 2026-11-10
phase: python
topic: Sqlalchemy ORM: sessions, relationships and lazy loading
---

# Sqlalchemy ORM: sessions, relationships and lazy loading

*Python for data engineering*

## Concept

SQLAlchemy ORM sessions manage the lifecycle of mapped objects—tracking their state, managing transactions, and handling dirty-object flushing. A session is your "identity map": it ensures that querying the same row twice returns the same Python object instance, preventing duplicate updates and inconsistent state. Without explicit session management, you lose this guarantee and queries become unpredictable; with poor session scope, you get "DetachedInstanceError" when accessing lazy-loaded relationships outside the session boundary.

Relationships (one-to-many, many-to-one) let you traverse foreign keys as object attributes instead of writing joins. Lazy loading determines *when* the related data is fetched: `lazy='select'` (default) fires a query only when you access the attribute, while `lazy='joined'` includes it upfront. This choice matters enormously for performance—one careless `job.postings` loop in a serializer can trigger N+1 queries.

In data pipelines, session scope must be deliberate: create a session at the start of a job, commit atomically, and close it cleanly. Accessing a lazy-loaded relationship after the session closes will fail unless you already loaded it or used `selectinload()`. Testing amplifies this: without careful fixtures, tests leak sessions or share state.

## Practice

**Problem:** You have job postings and need to report the job title and the count of locations where it appears, but the naive loop causes N+1 queries.

```sql
SELECT 
  jp.job_title_short,
  COUNT(DISTINCT jp.job_location) as location_count
FROM job_postings_fact jp
GROUP BY jp.job_title_short
ORDER BY location_count DESC;
```

**ORM solution (Python):**
```python
from sqlalchemy import func, select
from sqlalchemy.orm import Session

# ❌ BAD: N+1 problem
session = Session(engine)
titles = session.query(JobPosting.job_title_short).distinct().all()
for title in titles:
    count = session.query(JobPosting).filter(JobPosting.job_title_short == title).count()
    print(f"{title}: {count}")

# ✅ GOOD: Single query, explicit eager loading
stmt = (
    select(
        JobPosting.job_title_short,
        func.count(JobPosting.job_location.distinct()).label('location_count')
    )
    .group_by(JobPosting.job_title_short)
    .order_by(func.count(JobPosting.job_location).desc())
)
results = session.execute(stmt).all()
for title, count in results:
    print(f"{title}: {count}")
session.close()
```

## Notes

- **Session scope:** Always use context managers (`with Session(engine) as session:`) or dependency injection in tests; never pass detached objects between requests.
- **Lazy loading surprises:** `job.postings` works inside a session but fails after `.close()`—use `selectinload()` or `joinedload()` in the query if you know you'll need relationships later.
- **Testing:** Create a fresh, isolated session per test; use `rollback()` or in-memory SQLite with `create_all()` to avoid test pollution.
- **Type hints matter:** Define relationships with `Mapped[list[JobPosting]]` syntax (SQLAlchemy 2.0+) so mypy catches eager/lazy mismatches before runtime.
- **Adjacent topics:** Understand identity map behavior, session expunge, and the difference between `add()` and `merge()` when re-attaching objects from previous sessions.
