---
date: 2026-09-14
phase: python
topic: Glob patterns vs fnmatch for file matching
---

# Glob patterns vs fnmatch for file matching

*Python for data engineering*

## Concept

Glob patterns and fnmatch serve different purposes in file matching: **glob** finds actual files on disk using `*`, `?`, `**`, and `[]` syntax, while **fnmatch** matches strings against patterns without touching the filesystem. In data pipelines, this distinction matters because glob operations can fail silently (matching zero files when you expect thousands), and fnmatch lets you validate patterns programmatically before expensive operations. A common mistake is using glob to filter already-loaded filenames or treating glob results as sorted—they aren't guaranteed to be, which breaks reproducibility when processing data files in order.

Without distinguishing between these tools, you'll write fragile pipelines that mysteriously process nothing when directory structures shift, or that validate filenames inconsistently between environments. Type-checking glob results as `list[Path]` and using fnmatch in pure functions lets you test file matching logic without creating fixtures.

## Practice

**Problem:** You need to load only CSV files from a data lake directory, validate that filenames match your naming convention (e.g., `job_postings_YYYY-MM-DD.csv`), and fail fast if the pattern matches nothing. Ensure the solution is testable without mocking the filesystem.

```python
from pathlib import Path
from fnmatch import fnmatch
from datetime import datetime
import logging

def load_job_postings_csvs(data_dir: Path) -> list[Path]:
    """Load job_postings CSVs matching naming convention, sorted by date."""
    pattern = "job_postings_????-??-??.csv"
    matching_files: list[Path] = sorted(
        f for f in data_dir.glob("*.csv") if fnmatch(f.name, pattern)
    )
    
    if not matching_files:
        raise FileNotFoundError(
            f"No files matched pattern '{pattern}' in {data_dir}"
        )
    
    logging.info(f"Found {len(matching_files)} job_postings files")
    return matching_files

# Testable validation without filesystem access
def is_valid_postings_filename(filename: str) -> bool:
    """Pure function: test filename validity independently."""
    return fnmatch(filename, "job_postings_????-??-??.csv")

# Test example
assert is_valid_postings_filename("job_postings_2024-01-15.csv") is True
assert is_valid_postings_filename("job_postings_2024-1-15.csv") is False
assert is_valid_postings_filename("postings_2024-01-15.csv") is False
```

## Notes

- **Glob doesn't sort:** Always wrap results in `sorted()` if order matters for reproducible pipeline runs or partition processing.
- **Fnmatch vs regex:** Use fnmatch for simple wildcard patterns (`*`, `?`, `[abc]`); regex is overkill for filenames but essential for extracting values from matched names.
- **Empty glob is silent failure:** Check `if not matching_files:` and raise explicitly—silent processing of zero files is a common production bug.
- **`Path.glob()` vs `glob.glob()`:** Prefer `pathlib.Path` for type safety and method chaining; it returns `Path` objects directly instead of strings.
- **Adjacent topic—validation pipelines:** Combine fnmatch with `pydantic` validators to ensure filenames conform to schema before querying; this catches naming-convention drift early.
