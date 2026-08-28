---
date: 2026-08-28
phase: python
topic: Poetry and pip-tools for reproducible dependency management
---

# Poetry and pip-tools for reproducible dependency management

*Python for data engineering*

## Concept

Poetry and pip-tools solve the reproducibility crisis: **pip freeze captures installed versions, but not the dependency tree**. When you deploy a pipeline six months later, a transitive dependency has moved to v2.0 with breaking changes, and your job fails silently. Poetry locks both direct and transitive dependencies with hash verification; pip-tools does the same with simpler mechanics—you write `requirements.in`, run `pip-compile`, and commit `requirements.txt` with pinned versions and their source dependencies.

This matters acutely in data pipelines. A local SQLAlchemy 1.4 environment differs from production's 2.0. Your schema inference breaks. A colleague runs `pip install -r requirements.txt` three months later and gets a different dependency resolver order, introducing a subtle bug in pandas behavior. Without locked dependencies, **reproducibility becomes a myth**—you cannot reliably rerun a pipeline, backfill data, or debug production failures.

Poetry adds overhead: it's a Python project manager (not just a lock file tool). pip-tools is lighter: it generates `requirements.txt` directly from `requirements.in`, letting you stay in standard pip workflows while gaining determinism. Both integrate with CI/CD to fail fast when new transitive versions appear.

## Practice

**Problem:** Your data pipeline ingests job postings into `job_postings_fact`. New team members clone the repo, run `pip install -r requirements.txt`, and get different versions of `sqlalchemy` and `psycopg2`, causing subtle row-insertion failures and schema mismatches. You need to lock all dependencies, including transitive ones, so the pipeline behaves identically across machines and time.

**Solution (pip-tools workflow):**

```
# requirements.in (human-editable, lists only direct deps)
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
pandas==2.1.4
pytest==7.4.3

# Run: pip-compile requirements.in
# Generates: requirements.txt (with all transitive deps pinned by hash)

-c https://files.pythonhosted.org/packages/...
sqlalchemy==2.0.23 \
    --hash=sha256:abc123... \
    --hash=sha256:def456...
psycopg2-binary==2.9.9 \
    --hash=sha256:xyz789...
greenlet==3.0.1 \  # transitive from sqlalchemy
    --hash=sha256:ghi789...
pandas==2.1.4 \
    --hash=sha256:jkl012...
pytest==7.4.3 \
    --hash=sha256:mno345...

# Now: pip install -r requirements.txt
# Installs locked versions everywhere; hash validation prevents tampering.
```

Commit both `requirements.in` and `requirements.txt` to version control. Update only via `pip-compile requirements.in`, never manually edit `requirements.txt`.

## Notes

- **Transitive deps are the trap:** You pinned sqlalchemy but not its child greenlet. Six months later greenlet 3.1.0 drops Python 3.8 support, and your CI silently skips tests. Locking tools force you to name every dependency, every version.
- **Hash verification is underused:** pip-tools can add `--hash` flags; use them in production. They prevent package index tampering and force reproducibility at install time, not just lock-file time.
- **Poetry vs pip-tools trade-off:** Poetry is a full dependency resolver and project scaffolder (like Node's npm); pip-tools is a thin compile layer over pip. Choose pip-tools for existing pip workflows; choose Poetry if you're building a library or new project from scratch.
- **Update strategy matters:** `pip-compile --upgrade` rewrites all versions; `pip-compile --upgrade-package sqlalchemy` updates only one. Automate this in CI monthly to catch breaking changes early, not in production.
- **Adjacent: pre-commit hooks, Docker layer caching, and environment markers** (`python_version >= "3.9"`). Combine pip-tools with `pre-commit` to prevent committing `requirements.txt` without running `pip-compile`, and pin base image digests in Dockerfile to lock OS deps too.
