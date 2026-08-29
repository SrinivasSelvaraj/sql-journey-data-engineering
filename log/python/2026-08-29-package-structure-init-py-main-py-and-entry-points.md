---
date: 2026-08-29
phase: python
topic: Package structure: __init__.py, __main__.py and entry points
---

# Package structure: __init__.py, __main__.py and entry points

*Python for data engineering*

## Concept

A Python package needs three structural elements to be production-ready: `__init__.py` declares the package and controls what gets imported; `__main__.py` makes the package executable with `python -m mypackage`; and entry points (defined in `pyproject.toml` or `setup.py`) create CLI commands that install alongside your package. Without these, your code lives in isolated modules—no clear entry point for orchestration, no way to run it as a command-line tool, and imports become fragile when dependencies change paths. This matters most in data pipelines where you need to schedule jobs, pass configuration cleanly, and ensure your code works identically in dev, testing, and production environments.

The `__init__.py` file also sets the namespace: use it to expose your public API (e.g., `from mypackage import load_job_data`) rather than forcing users to dig into submodules. `__main__.py` lets you invoke the package as a module, which avoids hardcoding script locations in cron jobs or Airflow DAGs. Entry points bypass shell script wrappers entirely—they compile to executable stubs that call your Python function, so your CLI behaves like native commands (`my-pipeline --config config.yaml` instead of `python -m mypackage.cli --config config.yaml`).

## Practice

**Problem:** You have a data pipeline that extracts job postings, transforms them into a fact table, and loads them daily. Currently it's scattered across three modules: `extract.py`, `transform.py`, and `load.py`. When you try to schedule it with Airflow, the import paths break because Airflow runs it from a different working directory. You need a single, testable entry point.

```sql
-- Target schema (PostgreSQL)
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(50),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
);

-- Solution structure:
-- mypackage/
--   __init__.py          → exposes load_job_data()
--   __main__.py          → calls main() when run as module
--   etl/
--     extract.py        → query source systems
--     transform.py      → clean, type-check salary_year_avg, job_posted_date
--     load.py           → INSERT INTO job_postings_fact
--   cli.py              → argument parsing
--   config.py           → connection strings, schemas

-- In __init__.py:
from mypackage.etl.extract import extract_postings
from mypackage.etl.transform import transform_postings
from mypackage.etl.load import load_postings
def load_job_data(config_path: str) -> int:
    """Returns row count loaded."""
    raw = extract_postings(config_path)
    clean = transform_postings(raw)
    return load_postings(clean, config_path)

-- In __main__.py:
from mypackage.cli import main
if __name__ == "__main__":
    main()

-- In pyproject.toml:
[project.scripts]
my-pipeline = "mypackage.cli:main"

-- Result: now you can run:
-- python -m mypackage --config prod.yaml
-- OR after install: my-pipeline --config prod.yaml
```

## Notes

- **`__init__.py` is not optional in Python 3.3+** unless using namespace packages—but always include it to control your public API and avoid accidental circular imports.
- Entry points in `pyproject.toml` are the modern standard; `setup.py` is legacy. Entry points also work seamlessly in containerized environments (Docker doesn't care about shell `$PATH` issues).
- **Common mistake:** putting business logic in `__main__.py` makes it untestable; always call a function defined in a regular module from `__main__.py`.
- **Adjacent topics:** logging setup should happen *after* imports but before `main()` runs; configuration loading (via `argparse` or `Pydantic`) belongs in `cli.py`, not in modules; type hints on all entry point functions catch CLI argument mismatches early.
- **Revisit when:** adding async support (use `asyncio.run()` in `__main__.py`), integrating with workflow schedulers (Airflow DAGs will import your package entry point, not execute `__main__.py`), or refactoring monolithic pipelines into composable tasks.
