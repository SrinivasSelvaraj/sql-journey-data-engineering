---
date: 2026-11-10
phase: python
topic: CSV reading: dialect detection and type inference
---

# CSV reading: dialect detection and type inference

*Python for data engineering*

## Concept

CSV files lack standardized structure—delimiters vary (comma, semicolon, tab), quoting rules differ, and line endings are platform-dependent. **Dialect detection** automatically identifies these formatting parameters rather than hardcoding assumptions. **Type inference** attempts to infer column data types (int, float, date, bool) from sample rows, avoiding the brittle approach of treating everything as strings.

Both matter because production pipelines receive CSVs from unknown sources: legacy systems, external vendors, user uploads. A pipeline that assumes comma delimiters or treats "2024-01-15" as a string wastes downstream processing and introduces silent type mismatches. Without detection, you either fail loudly (wrong delimiter → parse errors) or fail silently (dates as strings → comparison bugs, aggregation failures).

The cost of skipping this: manual dialect specification per source, manual type casting in every query, data quality issues discovered late. Detection trades upfront sampling complexity for robustness across file variants.

## Practice

**Problem:** Load `job_postings_fact` from a vendor CSV where the dialect and types are unknown. Some rows have missing salary data. Build a robust loader that detects format and infers types, then validate before insertion.

```python
import csv
from pathlib import Path
from datetime import datetime
from typing import Any

def detect_and_load_job_postings(csv_path: str) -> list[dict[str, Any]]:
    """Detect dialect and infer types for job_postings_fact CSV."""
    
    # Detect dialect by sampling
    with open(csv_path, 'r', encoding='utf-8') as f:
        sample = f.read(8192)
    
    dialect = csv.Sniffer().sniff(sample, delimiters=',;\t|')
    
    # Infer types by examining first 100 rows
    rows_raw = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, dialect=dialect)
        rows_raw = [row for i, row in enumerate(reader) if i < 100]
    
    type_map = _infer_types(rows_raw, ['salary_year_avg', 'job_posted_date'])
    
    # Full load with type coercion
    rows_coerced = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, dialect=dialect)
        for row in reader:
            coerced = _coerce_row(row, type_map)
            if _validate_job_posting(coerced):
                rows_coerced.append(coerced)
    
    return rows_coerced

def _infer_types(sample_rows: list[dict], nullable_cols: list[str]) -> dict[str, type]:
    """Infer column types from sample."""
    types = {}
    if not sample_rows:
        return types
    
    for col in sample_rows[0].keys():
        values = [r.get(col, '').strip() for r in sample_rows if r.get(col, '').strip()]
        
        if not values:
            types[col] = str
        elif all(_is_bool(v) for v in values):
            types[col] = bool
        elif all(_is_int(v) for v in values):
            types[col] = int
        elif all(_is_float(v) for v in values):
            types[col] = float
        elif all(_is_date(v) for v in values):
            types[col] = 'date'
        else:
            types[col] = str
    
    return types

def _coerce_row(row: dict[str, str], type_map: dict[str, type]) -> dict[str, Any]:
    """Coerce row values to inferred types."""
    coerced = {}
    for col, val in row.items():
        if not val or not val.strip():
            coerced[col] = None
        elif type_map.get(col) == int:
            coerced[col] = int(val)
        elif type_map.get(col) == float:
            coerced[col] = float(val)
        elif type_map.get(col) == bool:
            coerced[col] = val.lower() in ('true', '1', 'yes')
        elif type_map.get(col) == 'date':
            coerced[col] = datetime.strptime(val, '%Y-%m-%d').date()
        else:
            coerced[col] = val.strip()
    return coerced

def _validate_job_posting(row: dict) -> bool:
    """Validate row has required fields and sensible values."""
    required = ['job_id', 'job_title_short']
    return all(row.get(col) for col in required) and (row.get('
