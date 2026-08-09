---
date: 2026-08-09
phase: python
topic: Packaging a pipeline with pyproject.toml
---

# Packaging a pipeline with pyproject.toml

*Python for data engineering*

## Concept

A `pyproject.toml` file is the modern Python packaging standard that declares your project's metadata, dependencies, and build system in a single configuration file. For data pipelines, it replaces scattered setup.py files and allows you to define exactly which versions of pandas, sqlalchemy, pytest, and other tools your pipeline needs—ensuring reproducibility across environments and CI/CD systems.

Without `pyproject.toml`, you'll face "works on my machine" problems: a colleague runs your pipeline with pandas 2.0 while you developed on 1.5, and mysteriously the dtypes or behavior change. You also can't easily install your pipeline code as a package, making testing and deployment fragile. The file becomes critical when you need to version your pipeline, run it in containers, or collaborate with others—which is every serious data engineering project.

The minimal structure includes `[build-system]`, `[project]` with name/version/dependencies, and optional `[project.optional-dependencies]` for dev/test extras. This single source of truth lets pip, poetry, or other tools install your pipeline consistently everywhere.

## Practice

**Problem:** You're building an ETL pipeline that reads job posting data, validates salary values aren't null or negative, transforms dates, and writes to a fact table. Your pipeline imports custom modules and needs pytest, pandas, sqlalchemy, and python-dotenv. You want to ensure anyone cloning the repo gets the exact same dependency versions.

```toml
[build-system]
requires = ["setuptools>=68.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "job-postings-etl"
version = "0.1.0"
description = "ETL pipeline for job postings fact table"
requires-python = ">=3.10"
dependencies = [
    "pandas>=2.0,<3.0",
    "sqlalchemy>=2.0,<3.0",
    "python-dotenv>=1.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4",
    "pytest-cov>=4.1",
    "black>=23.0",
    "mypy>=1.5",
]

[project.scripts]
run-etl = "job_postings_etl.main:run_pipeline"

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = "test_*.py"
```

Install with: `pip install -e ".[dev]"` (includes dev tools) or `pip install .` (production only).

## Notes

- **Pin major versions, not micro.** `pandas>=2.0,<3.0` catches breaking changes but allows security patches; avoid `pandas==2.0.1` which becomes stale within weeks.
- **Separate dev and prod dependencies.** Dev tools (pytest, black, mypy) bloat production images; use `optional-dependencies` to keep containers lean.
- **Use `[project.scripts]`** to create CLI entry points—replaces brittle shell scripts calling `python -m` and lets your pipeline be invoked directly.
- **Revisit: `pyproject.toml` also configures black, mypy, pytest**—consolidate all tool settings here rather than scattered `.flake8` and `setup.cfg` files.
- **Test locally with `pip install -e .`** before pushing; editable installs let you develop and catch import/version issues early.
