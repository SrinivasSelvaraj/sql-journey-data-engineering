---
date: 2026-08-10
phase: python
topic: CLI design with argparse or typer
---

# CLI design with argparse or typer

*Python for data engineering*

## Concept

A CLI (Command Line Interface) framework turns your data pipeline into a robust, documented tool that end users can actually invoke without reading your code. `argparse` is Python's standard library option—verbose but battle-tested; `typer` is newer, uses type hints for automatic validation and help text, and requires less boilerplate. Both matter because pipelines fail silently when operators mistype arguments, pass wrong types, or forget required flags. Without a structured CLI, you're stuck with fragile `sys.argv` parsing, missing validation, and no auto-generated `--help`. In data engineering, this is the difference between a script you debug at 2am and one that tells users exactly what went wrong before it runs.

The key insight: your type hints and argument definitions become executable guardrails. A typer function signature like `def load_jobs(date: str, environment: str = "prod")` automatically validates that `date` was provided, converts environment to a string, and generates help text. If someone passes `--date "not-a-date"`, the framework catches it at parse time, not three steps into your pipeline when a connection fails.

## Practice

**Problem:** You need a CLI command that loads job postings into the `job_postings_fact` table. Users must provide a source file path, a target date (as YYYY-MM-DD), and optionally override the target environment (prod or staging). The command should validate the date format and file existence before touching the database.

```python
import typer
from pathlib import Path
from datetime import datetime
import sqlite3

app = typer.Typer()

@app.command()
def load_job_postings(
    source_file: Path = typer.Argument(..., help="Path to CSV file"),
    job_posted_date: str = typer.Option(..., help="Date in YYYY-MM-DD format"),
    environment: str = typer.Option("prod", help="Target environment: prod or staging"),
) -> None:
    """Load job postings from CSV into job_postings_fact table."""
    
    # Validate file exists
    if not source_file.exists():
        typer.echo(f"Error: File not found: {source_file}", err=True)
        raise typer.Exit(code=1)
    
    # Validate date format
    try:
        datetime.strptime(job_posted_date, "%Y-%m-%d")
    except ValueError:
        typer.echo(f"Error: Date must be in YYYY-MM-DD format, got {job_posted_date}", err=True)
        raise typer.Exit(code=1)
    
    # Validate environment
    if environment not in ("prod", "staging"):
        typer.echo(f"Error: Environment must be 'prod' or 'staging', got {environment}", err=True)
        raise typer.Exit(code=1)
    
    # Execute insert
    conn = sqlite3.connect(f"data_{environment}.db")
    cursor = conn.cursor()
    
    cursor.execute(f"""
        INSERT INTO job_postings_fact 
        (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
        SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, ?, job_location
        FROM job_postings_staging
        WHERE source_file = ?
    """, (job_posted_date, source_file.name))
    
    conn.commit()
    typer.echo(f"✓ Loaded {cursor.rowcount} rows into {environment}")
    conn.close()

if __name__ == "__main__":
    app()
```

**Usage:** `python pipeline.py load-job-postings data/jobs.csv --job-posted-date 2024-01-15 --environment prod`

## Notes

- **Mistake:** Validating input *inside* your pipeline logic instead of at the CLI boundary. Validation in `load_job_postings()` means errors happen late; validation in the CLI layer means bad data never reaches your database code.
- **Mistake:** Mixing secrets into CLI arguments (they appear in process listings). Use environment variables or config files for credentials; reserve CLI args for data paths and toggles.
- **Connects to:** Logging and error handling (CLI should gracefully report failures); environment-based configuration (dev/staging/prod); and testing (CLI functions should be unit-testable in isolation, with dependency injection).
- **Revisit:** Structured logging to track which CLI invocation triggered which pipeline run; exit codes (always `0` on success, non-zero on failure so orchestrators can retry); and `typer.progressbar()` for long-running operations so operators know the process hasn't hung.
- **Worth noting:** `argparse` is more portable for legacy systems; `typer` is faster to write and reads like normal Python. If your team already uses `click`, stick with it—the framework matters less than consistency.
