---
date: 2026-09-14
phase: python
topic: Method resolution order and cooperative multiple inheritance
---

# Method resolution order and cooperative multiple inheritance

*Python for data engineering*

## Concept

Method Resolution Order (MRO) is the sequence in which Python looks for a method or attribute in a hierarchy of classes, especially critical when using multiple inheritance. Python uses the C3 Linearization algorithm, which you can inspect via `ClassName.__mro__` or `help(ClassName)`. In data pipelines, this matters because you often layer concerns—validation mixins, logging mixins, database adapters—and without understanding MRO, you get unpredictable behavior: a validator might skip checks, a retry mechanism might not trigger, or a mock might fail to override the real implementation. Without proper MRO, cooperative multiple inheritance (where each class calls `super()` to pass control up the chain) breaks: parent methods get skipped, initialization chains fail, and debugging becomes a nightmare of "why isn't my method being called?"

## Practice

**Problem:** You have a `DataValidator` mixin that checks if salary values are positive, a `LoggingMixin` that logs all method calls, and a `JobPostingRepository` base class that fetches from the database. When you inherit from all three in `ValidatedJobRepository`, the salary validation never runs because the MRO chain is broken.

```sql
-- Schema for testing
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
);

-- Insert test data with invalid salary
INSERT INTO job_postings_fact 
VALUES (1, 'Data Engineer', -50000, TRUE, '2024-01-15', 'Remote');
INSERT INTO job_postings_fact 
VALUES (2, 'Data Engineer', 85000, FALSE, '2024-01-16', 'New York');
```

```python
# Wrong MRO: validator never runs
class ValidatedJobRepository(JobPostingRepository, DataValidator, LoggingMixin):
    pass

# Correct: use cooperative super(), ensure validation comes before repo
class DataValidator:
    def validate_salary(self, salary):
        if salary < 0:
            raise ValueError(f"Salary {salary} is invalid")
        return super().validate_salary(salary) if hasattr(super(), 'validate_salary') else True

class LoggingMixin:
    def fetch_jobs(self):
        print(f"Fetching jobs...")
        return super().fetch_jobs()

class JobPostingRepository:
    def fetch_jobs(self):
        return "SELECT * FROM job_postings_fact"

# Correct order: validators first, then repo
class ValidatedJobRepository(DataValidator, LoggingMixin, JobPostingRepository):
    def fetch_and_validate(self):
        self.validate_salary(85000)  # runs validation
        return self.fetch_jobs()     # runs logging, then repo
```

## Notes

- **Mistake: forgetting `super()` in mixins**—always use `super().method_name()` to keep the chain alive; explicit parent calls like `Parent.method(self)` break cooperative inheritance.
- **Mistake: wrong inheritance order**—put more specific/constraining classes (validators, checks) before general ones (database, logging); MRO is left-to-right depth-first.
- **Debugging MRO**—print `YourClass.__mro__` or use `inspect.getmro()` when behavior is mysterious; this single line saves hours.
- **Connects to**: composition over inheritance (often simpler than multiple inheritance for pipelines), dependency injection (cleaner than deep hierarchies), and test mocking (wrong MRO breaks mock.patch).
- **Revisit when**: adding a second mixin, using abstract base classes (ABCs), or inheriting from third-party libraries with their own hierarchies.
