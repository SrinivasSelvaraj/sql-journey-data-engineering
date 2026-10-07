---
date: 2026-10-07
phase: python
topic: ConfigParser and environment-based configuration
---

# ConfigParser and environment-based configuration

*Python for data engineering*

## Concept

ConfigParser and environment-based configuration let you externalize settings—database URLs, API keys, batch sizes, retry counts—so the same code runs safely across dev, test, and production without modification. Python's `configparser` module reads `.ini` or `.conf` files; environment variables (via `os.getenv()`) override them, creating a hierarchy. This matters because hardcoding credentials into pipelines causes security leaks, environment-specific bugs are hard to debug, and redeploying code just to change a threshold wastes time.

Without this separation, you end up with scattered magic strings, developers committing secrets to Git, and brittle scripts that break when moving between environments. A data pipeline reading from a dev database in production is a catastrophe. ConfigParser enforces a single source of truth for each environment and makes defaults explicit—if a key is missing, you catch it early.

## Practice

**Problem:** Your job postings ETL reads from a Postgres database and writes to a data warehouse. You need different connection strings for local testing (SQLite), CI (test Postgres), and production (prod Postgres with SSL), plus a configurable batch size for testing vs. production loads.

```ini
# config/default.conf
[database]
driver = sqlite:///jobs.db
batch_size = 100

[logging]
level = INFO

# config/production.conf
[database]
driver = postgresql://user:pass@prod-host:5432/warehouse
batch_size = 10000
ssl_mode = require

[logging]
level = WARNING
```

```python
import configparser
import os
from pathlib import Path

def load_config(env: str = None) -> configparser.ConfigParser:
    env = env or os.getenv('ENV', 'default')
    config = configparser.ConfigParser()
    
    config.read(Path('config/default.conf'))
    config.read(Path(f'config/{env}.conf'))  # overlays environment-specific
    
    # Environment variables override file values
    if db_url := os.getenv('DATABASE_URL'):
        config['database']['driver'] = db_url
    
    return config

# Usage in your pipeline
config = load_config()
db_driver = config.get('database', 'driver')
batch_size = config.getint('database', 'batch_size')
log_level = config.get('logging', 'level')
```

## Notes

- **Mistake:** Forgetting that `configparser.get()` returns strings—use `.getint()`, `.getfloat()`, `.getboolean()` to avoid type surprises.
- **Mistake:** Environment files in Git; use `.gitignore` for `config/production.conf` and `config/secrets.conf`, commit only templates or examples.
- **Connection:** Pairs with `pydantic` or dataclasses for validated config objects; consider moving to YAML (via PyYAML) if your config grows nested and complex.
- **Testing tie-in:** Pass a test config path to your ETL functions; avoids relying on global `os.getenv()` state and makes unit tests reproducible.
- **Revisit:** Twelve-factor app methodology emphasizes config-via-environment; this pattern is step one toward true cloud-native deployments (Kubernetes ConfigMaps, AWS Secrets Manager).
