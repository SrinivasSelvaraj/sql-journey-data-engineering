---
date: 2026-11-08
phase: python
topic: Click and typer: command-line interfaces for scripts
---

# Click and typer: command-line interfaces for scripts

*Python for data engineering*

## Concept

Click and Typer are Python libraries that transform functions into command-line interfaces (CLIs) with minimal boilerplate. Click is the lower-level, more flexible framework; Typer is built on Click and uses Python type hints for automatic argument parsing and validation. In data engineering, these matter because pipelines rarely run in isolation—they need to accept runtime parameters (file paths, date ranges, thresholds), validate inputs before expensive operations begin, and fail loudly on misconfiguration. Without a structured CLI layer, you end up parsing sys.argv manually, mixing validation logic into business code, or hardcoding parameters that should be configurable. Both libraries generate help text automatically, handle type coercion, and make your script testable because arguments become function parameters.

## Practice

**Problem:** You need a CLI script that loads job postings from a CSV file into a staging table. The script should accept a file path, an optional date filter (default today), and a dry-run flag. It must validate that the file exists and the date is valid before touching the database.

```python
import typer
from pathlib import Path
from datetime import date
import pandas as pd

app = typer.Typer()

@app.command()
def load_job_postings(
    file_path: Path = typer.Argument(..., help="Path to job_postings CSV"),
    filter_date: date = typer.Option(date.today(), help="Only load postings from this date forward"),
    dry_run: bool = typer.Option(False, help="Parse and validate without writing to database"),
) -> None:
    """Load job postings from CSV into staging table."""
    
    if not file_path.exists():
        typer.echo(f"Error: File not found: {file_path}", err=True)
        raise typer.Exit(code=1)
    
    df = pd.read_csv(file_path)
    df['job_posted_date'] = pd.to_datetime(df['job_posted_date']).dt.date
    df = df[df['job_posted_date'] >= filter_date]
    
    typer.echo(f"Loaded {len(df)} rows from {file_path}")
    
    if not dry_run:
        # Write to database
        typer.echo("Writing to staging table...")
    else:
        typer.echo("[DRY RUN] No data written")

if __name__ == "__main__":
    app()
```

Called as: `python script.py data/postings.csv --filter-date 2024-01-01` or `python script.py --help`

## Notes

- **Type hints are contracts:** Typer validates inputs match the declared type (date, int, Path) before your function runs. Bad input fails fast with clear error messages instead of deep in your logic.
- **Arguments vs Options:** Use `typer.Argument()` for required positional parameters; use `typer.Option()` for flags and named parameters. This distinction makes CLI intent clear.
- **Testing becomes trivial:** Call your function directly with Python objects (no shell parsing). Test `load_job_postings(Path("test.csv"), date(2024, 1, 1), dry_run=True)` without invoking the CLI.
- **Connect to pydantic models:** For complex pipelines, wrap CLI arguments into Pydantic models for validation beyond type hints (e.g., date must be in past, file size < 1GB).
- **Revisit error handling:** CLI scripts need both typed validation *and* graceful degradation—distinguish between "bad config" (exit 1) and "data issue" (log and continue or exit 2).
