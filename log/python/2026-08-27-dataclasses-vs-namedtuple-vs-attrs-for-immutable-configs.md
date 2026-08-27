---
date: 2026-08-27
phase: python
topic: Dataclasses vs NamedTuple vs attrs for immutable configs
---

# Dataclasses vs NamedTuple vs attrs for immutable configs

*Python for data engineering*

## Concept

Configuration objects permeate data pipelines—database credentials, API endpoints, file paths, sampling rates. Python offers three built-in ways to define immutable, typed configurations: `dataclasses` (Python 3.7+, mutable by default but can be frozen), `NamedTuple` (immutable, lightweight, tuple-like), and `attrs` (third-party, most flexible). For pipeline configs, immutability matters because a single mutable dict passed between tasks can silently corrupt state; typed definitions catch schema mismatches before runtime. Without clear config schemas, you inherit ambiguity: optional fields become `None` everywhere, validation logic scatters across modules, and testing spawns dozens of mock configurations.

`dataclasses` shine when you need default values and custom `__post_init__` validation logic; `NamedTuple` is ideal for lightweight, truly immutable tuples that serialize cleanly; `attrs` dominates when you need converters, validators, and slots. For data pipelines, frozen `dataclasses` or `NamedTuple` win because they're stdlib, integrate with `typing` and serialization tools (Pydantic bridges to JSON), and make intent clear: this config will not change once instantiated.

## Practice

**Problem:** You're building a job posting ETL. The pipeline reads raw CSVs with inconsistent date formats, missing salary fields, and redundant location strings. Your extraction, transformation, and load stages each need validated configs (source file path, target schema, retry limits). Without a schema, each stage invents its own validation, and tests require 15 different mock config dicts.

```sql
-- Schema for job_postings_fact
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(255)
);
```

**Solution:** Define immutable configs once, reuse everywhere.

```python
from dataclasses import dataclass
from typing import Optional
from datetime import datetime
import json

@dataclass(frozen=True)
class ExtractConfig:
    source_file: str
    delimiter: str = ","
    encoding: str = "utf-8"
    
    def __post_init__(self):
        if not self.source_file.endswith(('.csv', '.parquet')):
            raise ValueError(f"Unsupported format: {self.source_file}")

@dataclass(frozen=True)
class TransformConfig:
    salary_year_min: Optional[int] = None
    salary_year_max: Optional[int] = None
    remove_duplicates: bool = True
    date_format: str = "%Y-%m-%d"
    
    def __post_init__(self):
        if self.salary_year_min and self.salary_year_max:
            if self.salary_year_min > self.salary_year_max:
                raise ValueError("salary_year_min cannot exceed salary_year_max")

@dataclass(frozen=True)
class LoadConfig:
    target_table: str
    batch_size: int = 1000
    retry_limit: int = 3
    retry_delay_sec: int = 2
    
    def __post_init__(self):
        if self.batch_size < 1 or self.retry_limit < 1:
            raise ValueError("batch_size and retry_limit must be >= 1")

# Usage in pipeline
extract_cfg = ExtractConfig(source_file="job_postings_raw.csv")
transform_cfg = TransformConfig(salary_year_min=30000, salary_year_max=500000)
load_cfg = LoadConfig(target_table="job_postings_fact", batch_size=5000)

# Immutability enforced at runtime
# load_cfg.batch_size = 2000  # FrozenInstanceError!

# Easy to test with single, reusable fixture
def test_extract_with_valid_config():
    cfg = ExtractConfig(source_file="test.csv")
    assert cfg.encoding == "utf-8"

def test_transform_salary_validation():
    with pytest.raises(ValueError):
        TransformConfig(salary_year_min=500000, salary_year_max=30000)

def test_load_batch_size_validation():
    with pytest.raises(ValueError):
        LoadConfig(target_table="fact", batch_size=0)
```

## Notes

- **Frozen dataclasses are not deeply immutable:** if a field holds a mutable list, that list can still be modified. Use `field(default_factory=tuple)` or `attrs.frozen` with `slots=True` for true immutability.
- **NamedTuple works great for simple configs but lacks validators:** you must add validation logic outside the class definition. `dataclass` with `__post_init__` is more Pythonic for complex pipelines.
- **Serialization matters for job queues and
