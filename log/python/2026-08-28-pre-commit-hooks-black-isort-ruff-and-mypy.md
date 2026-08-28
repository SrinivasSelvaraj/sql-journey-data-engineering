---
date: 2026-08-28
phase: python
topic: Pre-commit hooks: black, isort, ruff and mypy
---

# Pre-commit hooks: black, isort, ruff and mypy

*Python for data engineering*

## Concept

Pre-commit hooks automate code quality checks before changes are committed to git. The four-tool stack addresses distinct problems: **black** enforces consistent formatting (no style debates), **isort** organizes imports alphabetically and by type, **ruff** catches logical errors and style violations at speed, and **mypy** enforces static type hints to catch type mismatches early. Without these, data pipelines accumulate technical debt quickly—a typo in a column name goes unnoticed until production, untyped functions accept wrong data shapes, and inconsistent code style makes collaboration harder.

In data engineering specifically, this matters because pipelines run unattended and fail silently. A pipeline that loads job posting data might have an untyped `transform()` function that assumes salary is always numeric; if a NULL sneaks through, the entire job fails at 2 AM. Pre-commit hooks catch these before they merge, reducing the gap between "looks good locally" and "production is broken."

Setting up pre-commit requires a `.pre-commit-config.yaml` file in your repo root that defines which tools run on which files, then running `pre-commit install` to activate git hooks. On every commit, these tools run automatically and either fix the code (black, isort) or block the commit until you fix it (ruff, mypy).

## Practice

**Problem:** A data pipeline function processes job postings but has untyped parameters, inconsistent imports, and no type checking. When salary is NULL or a string, the pipeline breaks silently.

```python
import pandas
from datetime import datetime
import os
from typing import Optional
import polars as pl

def calculate_salary_percentile(postings, salary_col, percentile):
    """Process job postings and return salary stats."""
    salaries = postings[salary_col].dropna()
    return salaries.quantile(percentile / 100)

def load_job_postings(file_path: str) -> pandas.DataFrame:
    data = pandas.read_csv(file_path)
    return data

def enrich_postings(df,location_filter=None):
    if location_filter:
        df = df[df['job_location'] == location_filter]
    return df
```

**Solution with pre-commit applied:**

```python
import os
from datetime import datetime
from typing import Optional

import pandas
import polars as pl

def calculate_salary_percentile(
    postings: pl.DataFrame,
    salary_col: str,
    percentile: float,
) -> float:
    """Process job postings and return salary stats."""
    salaries = postings[salary_col].drop_nulls()
    return salaries.quantile(percentile / 100)

def load_job_postings(file_path: str) -> pandas.DataFrame:
    data = pandas.read_csv(file_path)
    return data

def enrich_postings(
    df: pandas.DataFrame,
    location_filter: Optional[str] = None,
) -> pandas.DataFrame:
    if location_filter:
        df = df[df["job_location"] == location_filter]
    return df
```

Changes: imports sorted (os → datetime → third-party), all parameters and returns type-hinted, string quotes normalized to double, default argument typed as Optional, consistent spacing around operators.

## Notes

- **Common mistake:** Installing pre-commit but not committing `.pre-commit-config.yaml` to git; teammates won't have the same checks unless they're in the repo.
- **Skipping is tempting:** `git commit --no-verify` bypasses hooks; resist it. The 2 minutes of fixing issues now beats debugging production at 1 AM.
- **Mypy strictness:** Start with `--basic` mode and gradually increase to `--strict`; jumping straight to strict will fail on existing code and frustrate the team.
- **Connects to:** CI/CD pipelines (pre-commit is local; CI catches what slips through), testing (types make mocking easier), and data contracts (typed schemas enforce what columns you expect).
- **Revisit:** Configure pre-commit to run only on data pipeline code, not notebooks; notebooks break type checking and complicate workflows.
