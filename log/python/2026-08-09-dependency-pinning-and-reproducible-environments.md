---
date: 2026-08-09
phase: python
topic: Dependency pinning and reproducible environments
---

# Dependency pinning and reproducible environments

*Python for data engineering*

## Concept

Dependency pinning means locking your Python packages to specific versions in `requirements.txt` or `poetry.lock` rather than using loose ranges like `pandas>=1.0`. Without pinning, the same code runs against different library versions on different machines or dates, causing silent failures: a newer numpy changes numeric behavior, a pandas API shifts, a data validation library becomes stricter. In data pipelines this is catastrophic—your transformation that worked Tuesday might corrupt data Wednesday after an automatic update.

Reproducibility is the ability to run the exact same pipeline code and get identical results. It requires pinning not just direct dependencies but transitive ones (dependencies of dependencies). Tools like `pip freeze` or `poetry lock` capture the full dependency tree. This is non-negotiable for data engineering because pipelines are often run in scheduled, unattended contexts where you won't notice a subtle library behavior change until data quality metrics drift or downstream systems break.

The common mistake is using version ranges in production: `pandas>=1.2.0` or `numpy~=1.20`. Acceptable for local development, dangerous for CI/CD and deployed code. Pin everything to exact versions for reproducibility, then upgrade intentionally and test the upgrade before merging.

## Practice

**Problem**: Your data pipeline reads job postings and filters remote jobs. It runs fine locally, but fails silently in production after a pandas minor update—boolean filtering now coerces differently and your WHERE clause on `job_work_from_home` returns wrong results.

**Solution**:

```sql
-- requirements.txt (pinned versions)
pandas==2.0.3
numpy==1.24.3
sqlalchemy==2.0.20
python-dotenv==1.0.0

-- Python code using typed, defensive filtering
from typing import List
import pandas as pd

def filter_remote_jobs(df: pd.DataFrame) -> pd.DataFrame:
    """Safely filter to remote roles only."""
    # Explicit bool assertion, not relying on implicit coercion
    assert df['job_work_from_home'].dtype == 'bool', \
        f"Expected bool, got {df['job_work_from_home'].dtype}"
    
    remote = df[df['job_work_from_home'] == True].copy()
    return remote
```

Document your environment:
```bash
pip freeze > requirements.txt  # captures exact versions
poetry lock                     # if using Poetry
```

## Notes

- **Transitive hell**: Don't just pin top-level packages. `pip freeze` captures everything; use it. A minor update to pandas might pull in a new version of pyarrow that changes behavior downstream.
- **Connects to**: Docker containers (bake pinned versions into images), CI/CD pipelines (test against pinned deps before deploy), and typing (pinned versions prevent API drift that breaks type contracts).
- **Common mistakes**: Committing `requirements.txt` with loose ranges to git, using `pip install package` without recording the version, forgetting to re-pin after a security update.
- **Revisit regularly**: Set a cadence (monthly, quarterly) to audit and test dependency upgrades deliberately. Don't pin forever; drift from upstream is its own risk.
- **Tool choice matters**: `poetry` is stronger than pip for reproducibility (deterministic lock file), but `pip + requirements.txt` works if disciplined. Avoid `conda` for production pipelines if exact reproducibility is critical—it's less deterministic across platforms.
