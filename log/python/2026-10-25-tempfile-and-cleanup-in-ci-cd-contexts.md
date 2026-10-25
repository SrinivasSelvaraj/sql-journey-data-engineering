---
date: 2026-10-25
phase: python
topic: Tempfile and cleanup in CI/CD contexts
---

# Tempfile and cleanup in CI/CD contexts

*Python for data engineering*

## Concept

Temporary files are essential in data pipelines but become liabilities in CI/CD without proper cleanup. When your pipeline reads raw data, transforms it via intermediate files, or writes test fixtures, those files persist on disk unless explicitly removed—consuming storage, polluting test isolation, and failing subsequent runs when paths conflict. In CI/CD environments (GitHub Actions, GitLab CI, Jenkins), temp files are particularly dangerous because runners may be reused across jobs; a temp file left behind in `/tmp` or a project directory can cause flaky tests or silent data corruption.

The core issue: **responsibility matters**. If a fixture creates `/tmp/jobs_raw_20250115.csv` but never deletes it, the next test run finds stale data. Context managers and try-finally blocks enforce cleanup, but only if you use them. Without cleanup discipline, your pipeline appears to work locally (where you manually clean `__pycache__` and temp dirs) but fails mysteriously in CI where the environment is immutable between runs.

## Practice

**Problem:** Your data pipeline reads a CSV into a staging temp file, applies transformations, and loads into a fact table. Tests pass locally but fail in CI because temp files accumulate and interfere with subsequent job runs. Write a pattern that ensures cleanup even if transformation fails.

```python
import tempfile
import os
from pathlib import Path
import pandas as pd

def load_job_postings_to_fact(raw_csv_path: str, fact_table_path: str) -> None:
    """
    Read raw job postings, transform, and write to fact table.
    Temp staging file is guaranteed cleanup via context manager.
    """
    with tempfile.NamedTemporaryFile(
        mode='w+',
        suffix='.csv',
        delete=False,  # Manual control
        dir='/tmp'
    ) as staging:
        staging_path = staging.name
    
    try:
        # Read and transform
        df = pd.read_csv(raw_csv_path)
        df['job_posted_date'] = pd.to_datetime(df['job_posted_date'])
        df['salary_year_avg'] = pd.to_numeric(df['salary_year_avg'], errors='coerce')
        df = df[df['salary_year_avg'].notna()]  # Drop nulls
        
        # Write staging
        df.to_csv(staging_path, index=False)
        
        # Load to fact table (pseudo-SQL)
        # INSERT INTO job_postings_fact SELECT * FROM staging...
        
        print(f"Loaded {len(df)} records to fact table")
    
    finally:
        # Cleanup guaranteed, even on exception
        if os.path.exists(staging_path):
            os.remove(staging_path)
```

## Notes

- **Use context managers when possible:** `tempfile.TemporaryDirectory()` as context manager auto-deletes on exit; only use `delete=False` + try-finally if you need the path before cleanup.
- **CI/CD state isolation:** Always assume the temp directory is shared and dirty. Use unique suffixes (timestamps, UUIDs) or isolate temp ops to test-scoped directories (pytest fixtures with `tmp_path`).
- **Connects to:** pytest fixtures (`tmp_path`, `tmp_path_factory`), Docker layer cleanup, artifact retention policies in CI config files.
- **Common mistake:** Creating temp files in the current working directory without relative paths; in CI, `cwd` may not be writable or may be shared across parallel jobs.
- **Revisit:** How to log temp file locations for debugging failed runs; setting `TMPDIR` env var in CI to sandbox temp writes; distinguishing between short-lived staging files and long-lived caches that should persist across pipeline stages.
