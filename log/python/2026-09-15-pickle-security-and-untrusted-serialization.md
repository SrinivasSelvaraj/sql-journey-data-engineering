---
date: 2026-09-15
phase: python
topic: Pickle security and untrusted serialization
---

# Pickle security and untrusted serialization

*Python for data engineering*

## Concept

Pickle is Python's native serialization format, but it executes arbitrary code during deserialization—making it a critical security vulnerability when deserializing untrusted data. In data pipelines, this matters when you load cached models, configuration objects, or intermediate results from external sources, databases, or user uploads. An attacker can craft a malicious pickle file that runs shell commands or exfiltrates data the moment you call `pickle.load()`.

The safer alternatives are JSON (human-readable, language-agnostic, safe by design) and formats like Parquet or Protocol Buffers (schema-enforced, efficient). If you must pickle, only deserialize data you've created yourself in controlled environments. For pipelines, this means: never pickle user input, never pickle data from APIs without validation, and never load pickled objects from untrusted filesystems without cryptographic verification (signing).

## Practice

**Problem:** You're building a job postings ETL pipeline. Team members cache intermediate DataFrames as pickles in a shared S3 bucket to speed up development. A contractor uploads a "job_postings_cache.pkl" file. Your pipeline does `df = pickle.load(open(file))` and processes it into the `job_postings_fact` table. How do you safely handle this?

```python
import json
import hashlib
from pathlib import Path
import pandas as pd

# ❌ UNSAFE
# df = pickle.load(open('job_postings_cache.pkl', 'rb'))

# ✅ SAFE: Use Parquet (schema-enforced, no code execution)
df = pd.read_parquet('job_postings_cache.parquet')

# ✅ SAFE: If you must accept user input, validate against schema
SCHEMA = {
    'job_id': 'int64',
    'job_title_short': 'object',
    'salary_year_avg': 'float64',
    'job_work_from_home': 'bool',
    'job_posted_date': 'datetime64[ns]',
    'job_location': 'object'
}

def load_and_validate(filepath: str) -> pd.DataFrame:
    """Load from safe format and validate schema."""
    df = pd.read_parquet(filepath)
    for col, dtype in SCHEMA.items():
        assert col in df.columns, f"Missing column: {col}"
        assert str(df[col].dtype) == dtype, f"Wrong dtype for {col}"
    return df

# ✅ SAFE: If legacy pickle exists, sign it with HMAC before sharing
import hmac

def sign_pickle(filepath: str, secret_key: str) -> str:
    """Create HMAC signature of pickle file."""
    with open(filepath, 'rb') as f:
        signature = hmac.new(secret_key.encode(), f.read(), hashlib.sha256).hexdigest()
    return signature

def load_signed_pickle(filepath: str, signature: str, secret_key: str) -> object:
    """Only load pickle if signature matches."""
    with open(filepath, 'rb') as f:
        data = f.read()
    expected_sig = hmac.new(secret_key.encode(), data, hashlib.sha256).hexdigest()
    assert hmac.compare_digest(signature, expected_sig), "Invalid signature: file tampered"
    return pickle.loads(data)
```

## Notes

- **Never deserialize pickle from user uploads, APIs, or untrusted storage.** This includes cached model files, configuration pickles, and intermediate DataFrames from shared buckets without verification.
- **Prefer Parquet for data workflows:** it's columnar, compressed, schema-validated, and safe. Use JSON for configs and metadata. Reserve pickle for *internal* caching (your own process memory, signed artifacts).
- **HMAC signing is not encryption:** it proves integrity, not confidentiality. Use it to detect tampering, but understand an attacker with the secret key can forge signatures.
- **Version your schemas and validate on load.** Even safe formats need field/type checks—garbage in, garbage out applies whether pickle is involved or not.
- **Connects to:** input validation patterns, data contract enforcement, secrets management (where you store HMAC keys), and supply-chain security in data pipelines.
