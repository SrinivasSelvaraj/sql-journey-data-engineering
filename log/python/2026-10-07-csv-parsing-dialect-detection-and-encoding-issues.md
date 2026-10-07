---
date: 2026-10-07
phase: python
topic: CSV parsing: dialect detection and encoding issues
---

# CSV parsing: dialect detection and encoding issues

*Python for data engineering*

## Concept

CSV files lack a formal specification, so dialect (delimiter, quoting style, line terminator) and encoding (UTF-8, Latin-1, Windows-1252) vary widely across sources. Python's `csv.Sniffer` can auto-detect dialect from a sample, and libraries like `chardet` infer encoding, but both are probabilistic—they fail silently on edge cases. Without explicit handling, a pipeline ingests corrupted rows, silent data loss (misaligned columns), or crashes mid-run when encoding assumptions break. This matters in production because bad CSV input is *common*: exports from legacy systems, user uploads, third-party data feeds. Detecting and failing fast (or gracefully repairing) is essential for survivability.

The key pattern: read a sample, detect dialect and encoding with fallback chains, validate against schema, then parse full file with typed validation. Use `errors='replace'` or `errors='ignore'` judiciously—log what was dropped—and always log the detected parameters so debugging is possible later.

## Practice

**Problem:** You ingest `job_postings.csv` from three vendors with different delimiters (comma vs. pipe), encodings (UTF-8 vs. Latin-1), and quote styles. Some rows have salary as `"45,000"` (quoted, with embedded comma); others are bare. You must load into `job_postings_fact` without crashes or silent truncation.

```python
import csv
import chardet
from pathlib import Path
from typing import Tuple
from dataclasses import dataclass
from io import TextIOWrapper

@dataclass
class CSVDialectMeta:
    encoding: str
    dialect: str
    detected_from_bytes: int

def detect_csv_params(file_path: Path, sample_size: int = 8192) -> CSVDialectMeta:
    """Detect encoding and dialect with fallback chain."""
    with open(file_path, 'rb') as f:
        raw_sample = f.read(sample_size)
    
    # Detect encoding
    enc_result = chardet.detect(raw_sample)
    encoding = enc_result.get('encoding') or 'utf-8'
    try:
        text_sample = raw_sample.decode(encoding)
    except (UnicodeDecodeError, LookupError):
        encoding = 'latin-1'
        text_sample = raw_sample.decode(encoding, errors='replace')
    
    # Detect dialect
    try:
        sniffer = csv.Sniffer()
        dialect = sniffer.sniff(text_sample, delimiters=',;\t|')
    except csv.Error:
        dialect = 'excel'  # fallback
    
    return CSVDialectMeta(encoding=encoding, dialect=dialect, detected_from_bytes=len(raw_sample))

def parse_csv_safe(file_path: Path, expected_cols: list[str]) -> list[dict]:
    """Parse CSV with detected params, validate schema, log issues."""
    meta = detect_csv_params(file_path)
    print(f"[INFO] Detected: encoding={meta.encoding}, dialect={meta.dialect}")
    
    rows = []
    with open(file_path, encoding=meta.encoding, errors='replace', newline='') as f:
        reader = csv.DictReader(f, dialect=meta.dialect)
        
        # Validate header
        if not reader.fieldnames or not set(expected_cols).issubset(set(reader.fieldnames)):
            raise ValueError(f"Expected columns {expected_cols}, got {reader.fieldnames}")
        
        for row_num, row in enumerate(reader, start=2):
            # Strip whitespace, validate required fields
            row = {k: v.strip() if v else None for k, v in row.items()}
            if not row.get('job_id'):
                print(f"[WARN] Row {row_num}: missing job_id, skipping")
                continue
            rows.append(row)
    
    print(f"[INFO] Parsed {len(rows)} rows from {file_path}")
    return rows

# Usage
job_postings = parse_csv_safe(
    Path('job_postings.csv'),
    expected_cols=['job_id', 'job_title_short', 'salary_year_avg', 'job_work_from_home', 'job_posted_date', 'job_location']
)
```

## Notes

- **`Sniffer` is not perfect:** it can misidentify delimiters in files with few rows or inconsistent quoting; always validate the first few rows manually in tests.
- **Encoding detection is probabilistic:** `chardet` uses heuristics and fails on mixed-encoding files or short samples; Latin-1 as a final fallback works because it accepts all byte values (but produces garbage).
- **Silent data loss:** `errors='replace'` substitutes bad bytes with `�`, which hides problems; log every substitution and consider `errors='strict'` in
