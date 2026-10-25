---
date: 2026-10-25
phase: python
topic: CSV dialect handling and encoding detection
---

# CSV dialect handling and encoding detection

*Python for data engineering*

## Concept

CSV files are deceivingly simple: they're text, so encoding matters (UTF-8, Latin-1, UTF-16 can coexist in a dataset), and dialect varies (delimiter, quote character, line terminator). Python's `csv` module and pandas can auto-detect, but auto-detection fails silently—producing garbled data that looks valid until downstream analysis breaks. Without explicit handling, you'll encounter mojibake (corrupted characters), silent row misalignment when delimiters aren't escaped correctly, and pipelines that work on 99% of files then crash on one.

The real issue: encoding and dialect are metadata, not data. You can't infer them reliably from content alone. A file with commas *and* semicolons as delimiters is ambiguous. A UTF-8 file with a stray Latin-1 byte is undetectable by simple heuristics. Production pipelines must declare expectations upfront, detect violations, and fail loudly with context—not silently corrupt.

## Practice

**Problem:** Your data lake receives job postings from three vendors with different CSV formats. Vendor A uses UTF-8 with commas; Vendor B uses Windows-1252 with semicolons; Vendor C uses UTF-8 with pipes and embedded newlines in quoted fields. You need to load all three into `job_postings_fact` without data loss or crashes.

```python
import csv
import chardet
from pathlib import Path
from typing import Tuple
import logging

def detect_encoding(file_path: Path, sample_size: int = 10000) -> str:
    """Detect file encoding using chardet on a sample."""
    with open(file_path, 'rb') as f:
        raw = f.read(sample_size)
    detected = chardet.detect(raw)
    confidence = detected.get('confidence', 0)
    encoding = detected.get('encoding', 'utf-8')
    
    if confidence < 0.7:
        logging.warning(f"{file_path}: low confidence {confidence}, defaulting to utf-8")
        return 'utf-8'
    return encoding

def detect_dialect(file_path: Path, encoding: str) -> csv.Dialect:
    """Detect CSV dialect using csv.Sniffer on first few lines."""
    with open(file_path, 'r', encoding=encoding, errors='replace') as f:
        sample = f.read(4096)
    
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=',;\t|')
        return dialect
    except csv.Error:
        logging.warning(f"{file_path}: dialect detection failed, using Excel")
        return csv.excel

def load_csv_safe(file_path: Path) -> list[dict]:
    """Load CSV with automatic encoding and dialect detection."""
    encoding = detect_encoding(file_path)
    logging.info(f"{file_path}: detected encoding={encoding}")
    
    dialect = detect_dialect(file_path, encoding)
    logging.info(f"{file_path}: detected delimiter={repr(dialect.delimiter)}, quotechar={repr(dialect.quotechar)}")
    
    rows = []
    with open(file_path, 'r', encoding=encoding, errors='replace') as f:
        reader = csv.DictReader(f, dialect=dialect)
        for i, row in enumerate(reader):
            if not any(row.values()):  # Skip empty rows
                continue
            rows.append(row)
            if i > 0 and i % 1000 == 0:
                logging.debug(f"Loaded {i} rows from {file_path}")
    
    return rows

# Usage in pipeline:
for vendor_file in Path('data/vendors').glob('*.csv'):
    rows = load_csv_safe(vendor_file)
    # Insert into job_postings_fact with schema validation
    for row in rows:
        # Map vendor fields to schema and validate types
        job_id = row.get('job_id') or row.get('id')
        job_title = row.get('job_title_short') or row.get('title')
        # ... continue mapping
```

## Notes

- **errors='replace'** is a safety valve—corrupted bytes become `?`—but log and alert when it triggers; that's a data quality issue upstream.
- **Confidence threshold on encoding detection** (0.7) is a heuristic; vendor contracts should specify encoding, then validate against that rather than auto-detecting.
- **Dialect detection is ambiguous** when delimiters repeat (e.g., "a,b,c" could use commas or be three single-character fields); context from schema or first row helps disambiguate.
- **Adjacent topics:** BOM handling (UTF-8-sig vs UTF-8), null-byte injection attacks in untrusted CSVs, and locale-specific number/date parsing (1,5 vs 1.5 across European/US formats).
- **Revisit:** Use `codecs.open()` for older
