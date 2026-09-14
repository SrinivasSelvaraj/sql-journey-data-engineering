---
date: 2026-09-14
phase: python
topic: Encoding issues: bytes vs str and UTF-8 BOM
---

# Encoding issues: bytes vs str and UTF-8 BOM

*Python for data engineering*

## Concept

In Python data pipelines, **bytes and str are different types**, and confusing them causes silent data corruption or crashes. A `str` is Unicode text; `bytes` is raw binary data. When reading files, network responses, or database outputs, you receive `bytes` and must explicitly decode to `str` using a codec (usually UTF-8). The reverse—encoding `str` to `bytes`—happens when writing or transmitting. A UTF-8 BOM (byte order mark) is a 3-byte sequence (`\xef\xbb\xbf`) at the start of some text files that signals "this is UTF-8." Python's UTF-8 codec includes the BOM by default on read, but leaves garbage characters if you don't strip it, corrupting CSV headers and field values downstream.

When this breaks: CSV readers fail to match expected column names; JSON parsers reject malformed strings; database inserts silently truncate or reject rows. The problem is insidious because small files work fine, but production data from Windows or legacy systems triggers failures at scale.

## Practice

**Problem:** A CSV of job postings exported from a legacy HR system includes a UTF-8 BOM. When you load it with `pd.read_csv()`, the first column name becomes `'\ufefjob_id'` instead of `'job_id'`. Your join against `job_postings_fact` fails, and salary and location fields don't match.

**Solution:**
```python
import pandas as pd

# Read CSV with BOM handling
df = pd.read_csv(
    'job_postings.csv',
    encoding='utf-8-sig'  # -sig strips BOM on decode
)

# Or manually if using raw file I/O:
with open('job_postings.csv', 'rb') as f:
    raw_bytes = f.read()
    text = raw_bytes.decode('utf-8-sig')  # Strip BOM during decode

# Validate: column names should match exactly
expected_cols = {'job_id', 'job_title_short', 'salary_year_avg', 
                 'job_work_from_home', 'job_posted_date', 'job_location'}
assert set(df.columns) == expected_cols, f"Unexpected columns: {set(df.columns)}"

# Write without BOM (standard practice)
df.to_csv('job_postings_clean.csv', index=False, encoding='utf-8')
```

## Notes

- **Always specify encoding explicitly** (`encoding='utf-8'` in pandas, `'utf-8'` in `open()`, `'utf-8-sig'` if BOM may be present). Never rely on locale defaults.
- **UTF-8-sig is read-only safe**: use it on input (`pd.read_csv(encoding='utf-8-sig')`), not output. Writing with `'utf-8-sig'` adds a BOM that downstream systems may reject.
- **Check for invisible characters**: if joins fail mysteriously, print `repr(df.columns[0])` to see escape sequences like `'\ufef'`.
- **Connects to**: CSV validation schemas (Great Expectations, pandera), type annotations for `bytes` vs `str` in function signatures, and robust file I/O testing with pathlib.
- **Revisit when**: integrating data from multiple sources (Excel exports, API responses, database dumps), and when writing tests—always include a fixture file with BOM to catch this in CI.
