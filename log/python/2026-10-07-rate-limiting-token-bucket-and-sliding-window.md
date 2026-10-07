---
date: 2026-10-07
phase: python
topic: Rate limiting: token bucket and sliding window
---

# Rate limiting: token bucket and sliding window

*Python for data engineering*

## Concept

Rate limiting protects downstream systems from being overwhelmed by controlling how many requests or events are processed in a time window. Two common strategies exist: **token bucket** generates tokens at a fixed rate (e.g., 100 requests/second) and each request consumes one token; **sliding window** tracks timestamps of actual events and rejects new ones if too many occurred recently (e.g., reject if >100 requests in last 60 seconds). Token bucket is simpler and allows short bursts, while sliding window is more precise but requires storing event timestamps. In data pipelines, rate limiting matters when calling external APIs (to respect quota), writing to databases (to avoid connection pool exhaustion), or processing streaming events (to prevent backpressure from overwhelming consumers).

Without rate limiting, a spike in traffic or a bug in your upstream data source can trigger cascading failures: API keys get blacklisted, database connections hang, and downstream workers crash waiting for resources. This is especially dangerous in production pipelines where a runaway job can take down shared infrastructure.

## Practice

**Problem:** Your pipeline ingests job postings from an external API with a 50 requests/second limit. Implement a token bucket rate limiter that pauses insertion into `job_postings_fact` until tokens are available, then logs when rate limiting was triggered.

```python
import time
from dataclasses import dataclass
from typing import List
import logging

logger = logging.getLogger(__name__)

@dataclass
class TokenBucket:
    capacity: int
    refill_rate: float  # tokens per second
    tokens: float = None
    last_refill: float = None
    
    def __post_init__(self):
        self.tokens = float(self.capacity)
        self.last_refill = time.time()
    
    def _refill(self) -> None:
        now = time.time()
        elapsed = now - self.last_refill
        self.tokens = min(self.capacity, self.tokens + elapsed * self.refill_rate)
        self.last_refill = now
    
    def acquire(self, tokens: int = 1, block: bool = True) -> bool:
        """Acquire tokens. If block=True, sleep until available."""
        while True:
            self._refill()
            if self.tokens >= tokens:
                self.tokens -= tokens
                return True
            if not block:
                return False
            sleep_time = (tokens - self.tokens) / self.refill_rate
            logger.warning(f"Rate limit hit. Sleeping {sleep_time:.2f}s")
            time.sleep(sleep_time)

def insert_job_postings(postings: List[dict], limiter: TokenBucket) -> int:
    """Insert postings with rate limiting. Returns count inserted."""
    inserted = 0
    for posting in postings:
        limiter.acquire(tokens=1, block=True)  # Wait for token
        # INSERT INTO job_postings_fact (job_id, job_title_short, ...) VALUES (...)
        inserted += 1
    return inserted

# Usage
limiter = TokenBucket(capacity=50, refill_rate=50.0)  # 50 req/sec
postings = [{"job_id": i, "job_title_short": "Engineer"} for i in range(200)]
insert_job_postings(postings, limiter)
```

## Notes

- **Token bucket gotcha:** If refill_rate exceeds capacity, tokens never fill; validate that `refill_rate ≤ capacity` or you'll silently rate-limit everything.
- **Sliding window is stateful:** Storing every event timestamp in memory works for small windows but scales poorly; consider time-bucketing (count per 1-second bucket) for large volumes.
- **Backpressure vs. rejection:** Token bucket *blocks* (applies backpressure); for strict rejection behavior (e.g., HTTP 429), use sliding window and fail fast instead.
- **Testing rate limiters:** Mock `time.time()` to avoid slow tests; verify token refill math with small numbers before running on production rates.
- **Adjacent topic:** Circuit breaker patterns (fail fast when downstream is unhealthy) complement rate limiting; use both to handle cascading failures and quota violations.
