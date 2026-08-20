---
date: 2026-08-20
phase: python
topic: Monkeypatching in tests vs dependency injection
---

# Monkeypatching in tests vs dependency injection

*Python for data engineering*

## Concept

Monkeypatching (replacing functions/objects at runtime in tests) is quick but fragile; dependency injection (passing dependencies as parameters) is explicit and testable. In data pipelines, you often fetch external data (APIs, databases, file systems) that you cannot control in tests. Monkeypatching lets you swap `requests.get` or a database connection without changing your function signature, but it makes dependencies invisible and tests brittle when code is refactored. Dependency injection forces you to declare what your function needs upfront, making the contract clear and allowing you to pass mock objects, stubs, or fixtures during testing without modifying global state.

The cost of not choosing wisely: monkeypatched tests fail mysteriously when you rename internal imports, and they hide what a function truly depends on. Code with injected dependencies is self-documenting and survives refactoring because the dependency chain is explicit in function signatures and type hints.

## Practice

**Problem:** You have a pipeline that loads job postings from a remote API and inserts them into a fact table. Your load function calls `requests.get()` directly, making it hard to test without hitting the real API.

```sql
-- job_postings_fact table
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10, 2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100)
);

-- BAD: monkeypatching approach (hidden dependency)
-- In your function: requests.get() called directly
-- In test: patch('requests.get', return_value=Mock(...))
-- Problem: What if requests is aliased or refactored?

-- GOOD: dependency injection approach
-- Function signature:
-- def load_job_postings(http_client: HttpClient, db_connection: Connection) -> None:
--     jobs = http_client.fetch_jobs()
--     for job in jobs:
--         db_connection.execute("""
--             INSERT INTO job_postings_fact 
--             (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
--             VALUES (%s, %s, %s, %s, %s, %s)
--         """, (job.id, job.title, job.salary, job.remote, job.date, job.location))
-- In test, pass MockHttpClient() and MockConnection() — no patching needed.
```

## Notes

- **Monkeypatching hides contracts:** a reader cannot see what `load_job_postings()` depends on without reading the function body and imports. Dependency injection makes it explicit in the signature.
- **Refactoring hazard:** if you monkeypatch `requests.get` and later refactor to use `httpx` instead, tests silently pass while real code breaks.
- **Scope pollution:** monkeypatching modifies global state, affecting other tests if they run in the same process; dependency injection is thread-safe and isolated.
- **Type hints are your ally:** `def load(client: HttpClient, conn: Connection)` + `@dataclass` mocks make testing trivial; combine with `abc.ABC` for protocol-based contracts.
- **Revisit: fixtures (pytest), context managers for setup/teardown, and the repository pattern** as a structured way to inject data access layers in pipelines.
