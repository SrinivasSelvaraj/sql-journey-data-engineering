---
date: 2026-09-13
phase: python
topic: Dependency injection for testable pipeline components
---

# Dependency injection for testable pipeline components

*Python for data engineering*

## Concept

Dependency injection (DI) means passing a component's dependencies (database connections, APIs, file systems, config) as arguments rather than hardcoding them inside the component. In data pipelines, this lets you swap a real database for a test double, a live API for a mock, or a production config for a test fixture—without changing the pipeline logic itself.

Without DI, your extraction function calls `psycopg2.connect("prod_db")` directly, your transform function instantiates its own logger, and your load function reaches for environment variables. When testing, you either skip testing (dangerous), hit real databases (slow and destructive), or rewrite the entire function (brittle). With DI, you pass a `connection` parameter, a `logger` parameter, and a `config` dict—your tests inject test doubles, production code injects real ones, and the logic remains unchanged.

This matters most when your pipeline reads from multiple sources, applies business rules, or writes to multiple destinations. A single hardcoded dependency can make a 50-line transform function untestable; five injected dependencies make it trivial to unit test in isolation.

## Practice

**Problem:** Your `load_job_postings` function must read from an S3 bucket, transform salary data (handle NULL, apply currency conversion), validate against a schema, and write to a Postgres table. If S3 is down, the schema service is slow, or Postgres is unreachable, you can't test the salary logic. The function is tightly coupled to three external systems.

**Solution:** Inject the S3 client, schema validator, and database connection as parameters. Mock them in tests, pass real instances in production.

```python
from typing import Protocol, List, Dict
from datetime import date
from dataclasses import dataclass

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: float | None
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

class S3Reader(Protocol):
    def get_object(self, bucket: str, key: str) -> bytes: ...

class SchemaValidator(Protocol):
    def validate(self, record: Dict) -> bool: ...

class Database(Protocol):
    def insert_batch(self, table: str, records: List[JobPosting]) -> int: ...

def load_job_postings(
    s3_client: S3Reader,
    validator: SchemaValidator,
    db: Database,
    bucket: str,
    key: str,
) -> int:
    """Load job postings from S3, validate, and insert to Postgres."""
    raw_data = s3_client.get_object(bucket, key)
    records = _parse_csv(raw_data)
    
    validated = [
        _to_job_posting(r)
        for r in records
        if validator.validate(r)
    ]
    
    return db.insert_batch("job_postings_fact", validated)

def _to_job_posting(record: Dict) -> JobPosting:
    salary = record.get("salary_year_avg")
    return JobPosting(
        job_id=int(record["job_id"]),
        job_title_short=record["job_title"],
        salary_year_avg=float(salary) if salary else None,
        job_work_from_home=record.get("remote", False),
        job_posted_date=date.fromisoformat(record["posted_date"]),
        job_location=record["location"],
    )

# Test example:
class FakeS3(S3Reader):
    def get_object(self, bucket: str, key: str) -> bytes:
        return b"job_id,job_title,salary_year_avg,remote,posted_date,location\n1,Engineer,120000,true,2024-01-15,Remote"

class FakeValidator(SchemaValidator):
    def validate(self, record: Dict) -> bool:
        return "job_id" in record and "salary_year_avg" in record

class FakeDB(Database):
    def __init__(self):
        self.inserted = []
    def insert_batch(self, table: str, records: List[JobPosting]) -> int:
        self.inserted.extend(records)
        return len(records)

def test_load_job_postings():
    s3 = FakeS3()
    validator = FakeValidator()
    db = FakeDB()
    
    count = load_job_postings(s3, validator, db, "jobs", "postings.csv")
    
    assert count == 1
    assert db.inserted[0].salary_year_avg == 120000
    assert db.inserted[0].job_work_from_home is True
```

## Notes

- **Mistake:** Using `Protocol` as a documentation aid only; actually instantiate test doubles that implement the protocol. Type hints alone don't guarantee testability.
- **Mistake:** Injecting too much (every logger, every
