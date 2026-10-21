---
date: 2026-10-21
phase: reliability
topic: Version pinning and dependency lock files
---

# Version pinning and dependency lock files

*Quality, reliability and the professional layer*

## Concept

Version pinning is the practice of explicitly specifying exact versions (or narrow version ranges) for all dependencies rather than allowing flexible upgrades. Without it, a pipeline that works today may break tomorrow when a dependency auto-updates—a transitive dependency changes behavior, a library deprecates a function you rely on, or a data connector alters output schema. This is especially critical in data engineering because failures often cascade silently: a subtle change in pandas behavior might corrupt your transformations without raising an error, or a Postgres driver update could change type coercion rules.

Lock files (like `requirements.txt`, `poetry.lock`, `Pipfile.lock`) go further: they capture the *exact* resolved dependency tree—every transitive dependency and its version—so that every environment (laptop, CI/CD, production) runs identical code. Without them, two engineers running `pip install -r requirements.txt` with loose version specs like `pandas>=1.3.0` could end up with different pandas versions and different results.

This is the line between "works for me" and "owns production data." Uncontrolled dependencies are a silent killer: they introduce non-determinism, make incidents harder to debug, and erode trust in data quality.

## Practice

**Problem:** Your `job_postings_fact` table calculates `salary_year_avg` from raw salary data using a Python transformation. After a routine `pip install`, the pipeline runs without error but produces salary values 10% higher than before. The root cause is a minor version bump in NumPy that changed floating-point rounding behavior.

**Solution:**

```sql
-- The transformation code depends on exact versions. Instead of:
-- requirements.txt: numpy>=1.20.0

-- Pin exact versions in requirements.txt:
numpy==1.23.5
pandas==1.5.3
sqlalchemy==2.0.1

-- Or, for production, generate and commit a lock file:
-- pip freeze > requirements.lock
-- Then install from the lock:
-- pip install -r requirements.lock

-- In your dbt project, use the same discipline:
-- dbt_project.yml or packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 0.9.2  -- pin, don't use 0.9.x or >=0.9.0
```

This ensures that on 2024-12-15, the same `salary_year_avg` calculation runs everywhere.

## Notes

- **Common mistake:** Committing `requirements.txt` with loose ranges (`package>=1.0`) and assuming CI will be "fresh." Environments diverge within weeks.
- **Testing blind spot:** Tests often pass locally but fail in CI because dependency versions differ. Always test against a lock file.
- **Connects to:** Docker/containers (which lock OS and system libraries), infrastructure-as-code, and reproducibility. A pinned environment + Docker = true reproducibility.
- **Revisit:** Dependency scanning tools (e.g., `dependabot`, `snyk`) help you *safely* update pins when security patches are available—not a free pass to unpin.
- **Transitive dependencies matter:** You don't control what `pandas==1.5.3` depends on, but your lock file does. Always commit lock files, not just top-level requirements.
