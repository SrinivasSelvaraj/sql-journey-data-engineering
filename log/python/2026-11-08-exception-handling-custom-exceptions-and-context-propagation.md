---
date: 2026-11-08
phase: python
topic: Exception handling: custom exceptions and context propagation
---

# Exception handling: custom exceptions and context propagation

*Python for data engineering*

## Concept

Custom exceptions allow you to signal domain-specific errors in data pipelines without conflating infrastructure failures with data quality issues. When a CSV row has a null salary or a date string fails to parse, you want to catch and handle that distinctly from a database connection timeout. Without custom exceptions, you end up catching generic `ValueError` or `Exception`, which masks the actual problem and makes debugging slow—you can't distinguish a bad input row from a malformed ETL configuration.

Context propagation means threading error information (source file, row number, attempted transformation, upstream job ID) through exception handlers so that logs and alerts tell you *where* the problem originated. A bare `raise` loses this chain; a well-designed exception stores metadata. In data pipelines, this is critical: if a job fails on row 50,000 of a 10-million-row load, you need to know the row number, the values that triggered it, and which transformation step broke, not just "an error occurred."

## Practice

**Problem:** Load job_postings_fact from a CSV source. Some rows have invalid salary values (negative, non-numeric, or out-of-range), missing locations, or malformed dates. You need to capture which rows fail, why, and continue processing valid rows while reporting failures.

```python
class DataValidationError(Exception):
    """Raised when input data fails validation."""
    def __init__(self, message, row_number=None, field=None, value=None):
        self.row_number = row_number
        self.field = field
        self.value = value
        context = f" [row {row_number}, field '{field}', value: {value}]" if row_number else ""
        super().__init__(f"{message}{context}")

class DateParseError(DataValidationError):
    """Raised when a date column cannot be parsed."""
    pass

def load_job_postings(csv_path):
    failed_rows = []
    loaded_rows = []
    
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row_num, row in enumerate(reader, start=1):
            try:
                salary = int(row['salary_year_avg'])
                if salary < 0 or salary > 10_000_000:
                    raise DataValidationError(
                        "Salary out of valid range",
                        row_number=row_num,
                        field='salary_year_avg',
                        value=row['salary_year_avg']
                    )
                
                job_date = datetime.strptime(row['job_posted_date'], '%Y-%m-%d').date()
                
                location = row.get('job_location', '').strip()
                if not location:
                    raise DataValidationError(
                        "Location is required",
                        row_number=row_num,
                        field='job_location',
                        value=None
                    )
                
                loaded_rows.append({
                    'job_id': row['job_id'],
                    'job_title_short': row['job_title_short'],
                    'salary_year_avg': salary,
                    'job_work_from_home': row['job_work_from_home'].lower() == 'true',
                    'job_posted_date': job_date,
                    'job_location': location
                })
            
            except (ValueError, KeyError) as e:
                failed_rows.append({
                    'row_number': row_num,
                    'error': str(e),
                    'raw_row': row
                })
            except DataValidationError as e:
                failed_rows.append({
                    'row_number': e.row_number,
                    'field': e.field,
                    'error': str(e),
                    'raw_row': row
                })
    
    if failed_rows:
        logger.warning(f"Loaded {len(loaded_rows)} rows; {len(failed_rows)} failed validation")
        for fail in failed_rows[:10]:  # Log first 10
            logger.error(f"Row {fail['row_number']}: {fail['error']}")
    
    return loaded_rows, failed_rows
```

## Notes

- **Don't catch and re-raise bare.** Always add context when you re-raise: `except SomeError as e: raise DataValidationError(f"Failed to parse job posting: {e}", row_number=i) from e`. The `from e` preserves the traceback chain.

- **Custom exceptions are inheritance hierarchies.** Create a base `PipelineError`, then subclass it for `DataValidationError`, `TransformError`, `LoadError`. Callers can catch at the level of granularity they need.

- **Store metadata in the exception, not just the message.** Row numbers, field names, attempted values—these belong in attributes, not stringified into the message. Logging and monitoring systems can then extract and index them.

- **Context propagation connects to observability
