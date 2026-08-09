---
date: 2026-08-09
phase: python
topic: Calling paginated REST APIs safely
---

# Calling paginated REST APIs safely

*Python for data engineering*

## Concept

Paginated REST APIs return results in chunks to avoid overwhelming servers and clients. Without safe pagination handling, you risk infinite loops (missing cursor updates), duplicate records (re-fetching same page), data loss (stopping early on transient errors), and rate-limit bans (hammering the endpoint). The "safe" part means: respecting backoff headers, validating page tokens before use, logging state for recovery, and distinguishing between "no more data" and "temporary failure."

When you're ingesting job postings from an external API, a single retry logic mistake can cause you to re-insert thousands of rows or miss entire batches. The cost isn't just duplicates in your warehouse—it's wasted API quota, stalled pipelines, and broken trust in your data freshness SLAs.

## Practice

**Problem:** Write a Python function that fetches job postings from a paginated API (`/jobs?page=1&limit=100`), stops cleanly on transient errors, and loads them into `job_postings_fact`. The API returns `{"data": [...], "next_page": null}` when exhausted and raises HTTP 429 (rate limit) with a `Retry-After` header.

```python
import time
import logging
from typing import Generator
from datetime import datetime
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

logger = logging.getLogger(__name__)

def safe_paginated_fetch(
    base_url: str,
    max_retries: int = 3,
    backoff_factor: float = 0.5
) -> Generator[dict, None, None]:
    """
    Safely fetch paginated API data with exponential backoff.
    Yields individual records; caller handles persistence.
    """
    session = requests.Session()
    retry_strategy = Retry(
        total=max_retries,
        backoff_factor=backoff_factor,
        status_forcelist=[429, 500, 502, 503, 504]
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("http://", adapter)
    session.mount("https://", adapter)

    next_page = 1
    page_count = 0

    while next_page is not None:
        try:
            url = f"{base_url}?page={next_page}&limit=100"
            logger.info(f"Fetching page {next_page} from {url}")
            
            response = session.get(url, timeout=10)
            response.raise_for_status()
            
            payload = response.json()
            records = payload.get("data", [])
            
            if not records:
                logger.info("No records on this page; stopping.")
                break
            
            for record in records:
                yield record
            
            next_page = payload.get("next_page")
            page_count += 1
            logger.info(f"Processed page {page_count} ({len(records)} records)")
            
        except requests.exceptions.Timeout:
            logger.error(f"Timeout on page {next_page}; stopping to avoid duplicate processing.")
            raise
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 429:
                retry_after = int(e.response.headers.get("Retry-After", 60))
                logger.warning(f"Rate limited; waiting {retry_after}s before retry.")
                time.sleep(retry_after)
                # Do NOT increment next_page; retry same page
                continue
            logger.error(f"HTTP error {e.response.status_code}; stopping.")
            raise
        except Exception as e:
            logger.error(f"Unexpected error fetching page {next_page}: {e}")
            raise

def load_job_postings(base_url: str, connection) -> int:
    """Fetch and insert job postings; return count inserted."""
    insert_count = 0
    for record in safe_paginated_fetch(base_url):
        cursor = connection.cursor()
        cursor.execute(
            """
            INSERT INTO job_postings_fact 
            (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (job_id) DO NOTHING
            """,
            (
                record["id"],
                record["title"],
                record.get("salary"),
                record.get("remote", False),
                datetime.fromisoformat(record["posted_at"]).date(),
                record.get("location", "")
            )
        )
        connection.commit()
        insert_count += 1
    
    logger.info(f"Load complete: {insert_count} records inserted or skipped.")
    return insert_count
```

## Notes

- **Don't increment the page cursor until you've safely logged the fetch
