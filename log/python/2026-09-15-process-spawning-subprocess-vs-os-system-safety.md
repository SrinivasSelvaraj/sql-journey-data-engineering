---
date: 2026-09-15
phase: python
topic: Process spawning: subprocess vs os.system safety
---

# Process spawning: subprocess vs os.system safety

*Python for data engineering*

## Concept

`os.system()` passes commands directly to the shell as a single string, making it vulnerable to shell injection attacks when untrusted input is concatenated into the command. If a job title or file path contains shell metacharacters (`;`, `|`, `$()`, backticks), an attacker can execute arbitrary code. The `subprocess` module, by contrast, accepts arguments as a list, bypassing shell interpretation entirely when `shell=False` (the default). This separation between command and arguments is critical in data pipelines where input comes from databases, APIs, or user-provided files. Without it, a malicious job posting title like `; rm -rf /` embedded in a CSV could destroy your entire system during ETL processing.

The safety difference is absolute: `os.system("curl " + url)` is always dangerous; `subprocess.run(["curl", url])` is safe because the URL is passed as data, never interpreted as code. Additionally, `subprocess` provides better error handling, return code inspection, and timeout support—all necessary for production pipelines that must survive bad input gracefully.

## Practice

**Problem:** Your data pipeline downloads job postings from an external API and stores them in a database. A downstream script needs to compress and archive old CSV exports by calling `gzip`. Some job titles or file paths might contain spaces, quotes, or special characters. Using string concatenation with `os.system()` risks injection; you need a safe, testable approach.

```python
import subprocess
from pathlib import Path
from typing import Optional

def archive_job_postings(csv_path: str, archive_dir: str, timeout: int = 30) -> bool:
    """Safely compress job postings CSV using subprocess."""
    try:
        csv_file = Path(csv_path)
        if not csv_file.exists():
            raise FileNotFoundError(f"CSV file not found: {csv_path}")
        
        archive_path = Path(archive_dir)
        archive_path.mkdir(parents=True, exist_ok=True)
        
        # subprocess with list args—never shell=True
        result = subprocess.run(
            ["gzip", "-c", str(csv_file)],
            stdout=open(archive_path / f"{csv_file.stem}.gz", "wb"),
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False
        )
        
        if result.returncode != 0:
            print(f"gzip failed: {result.stderr.decode()}")
            return False
        return True
    
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        print(f"Archive failed: {e}")
        return False
```

## Notes

- **Never use `shell=True`** unless you control 100% of the command string; it re-enables shell injection regardless of using `subprocess`.
- **Always pass arguments as a list** to `subprocess.run()`, `subprocess.Popen()`, etc.—this is the core safety mechanism.
- **Validate paths and timeouts**: use `pathlib.Path.exists()` before execution and set `timeout=` to prevent hung processes in long-running pipelines.
- **Check return codes**: `check=False` allows graceful handling; `check=True` raises `CalledProcessError` on non-zero exit, useful for fail-fast semantics.
- **Related:** shell escaping libraries (`shlex.quote()`), logging subprocess errors for observability, and containerization (Docker) as defense-in-depth against injection in data workflows.
