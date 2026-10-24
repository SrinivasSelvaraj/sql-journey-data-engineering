---
date: 2026-10-24
phase: python
topic: Custom error hierarchies and context in pipelines
---

# Custom error hierarchies and context in pipelines

*Python for data engineering*

## Concept

Custom error hierarchies let you catch, handle, and propagate failures in data pipelines with semantic precision. Instead of generic `Exception` or `ValueError`, you define domain-specific exceptions (e.g., `DataValidationError`, `SchemaMismatchError`, `ExternalAPIError`) that encode *what went wrong* and *where*. This matters because pipelines touch many failure modes—malformed input, missing dependencies, API timeouts, constraint violations—and each deserves different recovery logic. Without custom hierarchies, you either catch everything (masking real bugs) or catch nothing (crashes propagate up and fail the whole job). With them, you trap errors at the right layer, attach context (row numbers, column names, upstream job IDs), and decide: retry, skip, alert, or fail gracefully.

## Practice

**Problem:** A data pipeline loads `job_postings_fact` from a CSV. The `salary_year_avg` column sometimes contains non-numeric strings, `job_posted_date` is occasionally malformed, and the location field can be NULL when a job is remote but `job_work_from_home` is FALSE—a logical inconsistency that breaks downstream analytics.

**Solution:**

```python
class PipelineError(Exception):
    """Base exception for all pipeline failures."""
    def __init__(self, message: str, context: dict = None):
        self.message = message
        self.context = context or {}
        super().__init__(f"{message} | context: {self.context}")

class DataValidationError(PipelineError):
    """Raised when a row violates schema or business rules."""
    pass

class SchemaMismatchError(PipelineError):
    """Raised when incoming data columns/types don't match expected schema."""
    pass

def load_job_postings(csv_path: str) -> list[dict]:
    """Load and validate job_postings_fact; raise custom errors with row context."""
    records = []
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row_num, row in enumerate(reader, start=2):  # start=2 to account for header
            try:
                # Check required columns exist
                required = {'job_id', 'job_title_short', 'salary_year_avg', 
                            'job_work_from_home', 'job_posted_date', 'job_location'}
                if not required.issubset(row.keys()):
                    raise SchemaMismatchError(
                        "Missing required columns",
                        context={'row': row_num, 'missing': required - set(row.keys())}
                    )
                
                # Validate salary
                try:
                    salary = float(row['salary_year_avg']) if row['salary_year_avg'] else None
                except ValueError:
                    raise DataValidationError(
                        f"salary_year_avg is not numeric: '{row['salary_year_avg']}'",
                        context={'row': row_num, 'job_id': row['job_id']}
                    )
                
                # Validate date
                try:
                    posted = datetime.strptime(row['job_posted_date'], '%Y-%m-%d').date()
                except ValueError:
                    raise DataValidationError(
                        f"job_posted_date malformed: '{row['job_posted_date']}'",
                        context={'row': row_num, 'job_id': row['job_id']}
                    )
                
                # Validate remote/location consistency
                is_remote = row['job_work_from_home'].lower() == 'true'
                location = row['job_location'].strip() if row['job_location'] else None
                if is_remote and location:
                    pass  # OK: remote job with location info
                elif not is_remote and not location:
                    raise DataValidationError(
                        "On-site job missing location",
                        context={'row': row_num, 'job_id': row['job_id']}
                    )
                
                records.append({
                    'job_id': row['job_id'],
                    'job_title_short': row['job_title_short'],
                    'salary_year_avg': salary,
                    'job_work_from_home': is_remote,
                    'job_posted_date': posted,
                    'job_location': location
                })
            except PipelineError as e:
                print(f"Validation failed: {e}")
                # Decide: skip row, retry, or re-raise
                if e.context.get('severity') == 'critical':
                    raise
                continue
    
    return records
```

## Notes

- **Hierarchy depth matters:** `PipelineError` → `DataValidationError` / `ExternalAPIError` / `StorageError` allows `except DataValidationError` to catch specific failures while `except PipelineError` still catches all. Avoid
