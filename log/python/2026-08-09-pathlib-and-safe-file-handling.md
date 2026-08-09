---
date: 2026-08-09
phase: python
topic: pathlib and safe file handling
---

# pathlib and safe file handling

*Python for data engineering*

## Concept

`pathlib.Path` replaces string-based file operations with an object-oriented interface that handles OS differences automatically—forward slashes work everywhere, path joining is safe, and you avoid manual string concatenation bugs. Without it, data pipelines often fail silently when moving between Linux/Windows, or crash when input paths contain unexpected separators, missing parents, or symbolic links.

In data engineering, file handling is a pipeline's weakest point. CSV ingestion scripts assume `/data/raw/` exists; it doesn't. Transformation jobs write to hardcoded paths that only work on the author's machine. Pathlib forces you to check existence, create parents atomically, resolve symlinks, and make paths absolute before passing them to downstream tools—all in readable code.

The alternative—string manipulation with `os.path.join()` and manual existence checks—scatters defensive logic across your codebase and remains fragile. Pathlib centralizes it: `.exists()`, `.mkdir(parents=True, exist_ok=True)`, `.resolve()`, `.glob()` for pattern matching.

## Practice

**Problem:** Your ETL reads job postings from a CSV in a `raw/` folder, validates salary data, and writes clean records to `processed/`. The folder structure might not exist; paths differ across dev/prod; you need to log exactly which file was read.

```python
from pathlib import Path
import csv
from typing import Iterator

def load_job_postings(raw_dir: str) -> Iterator[dict]:
    """Safely load job postings CSV, creating and validating paths."""
    raw_path = Path(raw_dir).resolve()
    
    if not raw_path.exists():
        raise FileNotFoundError(f"Raw data directory does not exist: {raw_path}")
    
    csv_file = raw_path / "job_postings.csv"
    if not csv_file.is_file():
        raise FileNotFoundError(f"Expected CSV not found: {csv_file}")
    
    print(f"Reading from: {csv_file.absolute()}")
    
    with open(csv_file, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            yield row

def write_job_facts(processed_dir: str, records: Iterator[dict]) -> Path:
    """Write cleaned records, creating output directory safely."""
    out_path = Path(processed_dir).resolve()
    out_path.mkdir(parents=True, exist_ok=True)
    
    output_file = out_path / "job_postings_fact.csv"
    
    with open(output_file, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["job_id", "job_title_short", "salary_year_avg", "job_work_from_home", "job_posted_date", "job_location"])
        writer.writeheader()
        writer.writerows(records)
    
    return output_file
```

## Notes

- **Mistake:** Using `Path(user_input)` without `.resolve()`—symlinks and `..` traversal can escape intended boundaries; always call `.resolve()` before security checks.
- **Mistake:** Forgetting `.is_file()` vs `.exists()`—a directory can exist but `.is_file()` returns False; check the type you expect.
- **Connects to:** Type hints (`Path` not `str`) and input validation; treating file I/O as a data type forces you to validate early.
- **Worth revisiting:** `.glob("*.csv")` for batch ingestion; `.suffix` and `.stem` for dynamic filename parsing; context managers (`with`) for guaranteed cleanup.
- **Production pattern:** Keep data dirs in environment variables or config files, always `.resolve()`, and log the absolute path before reading—debugging "file not found" in prod is easier when you know exactly which path was attempted.
