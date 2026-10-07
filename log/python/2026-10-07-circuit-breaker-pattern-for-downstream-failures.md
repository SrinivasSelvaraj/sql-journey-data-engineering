---
date: 2026-10-07
phase: python
topic: Circuit breaker pattern for downstream failures
---

# Circuit breaker pattern for downstream failures

*Python for data engineering*

## Concept

The circuit breaker pattern prevents cascading failures by stopping repeated calls to a failing downstream service. When a service fails repeatedly (e.g., an API timeout, database connection pool exhaustion), the circuit breaker "trips" and immediately rejects new requests for a configured duration, allowing the dependency to recover without being hammered. This is critical in data pipelines where a transient failure in one stage (external API, warehouse connection, streaming ingestion) can propagate into retry storms that degrade the entire system.

Without circuit breakers, pipelines retry failed calls with exponential backoff or fixed intervals, but if the downstream dependency is overwhelmed or recovering, those retries add load and delay upstream stages. In data contexts—where jobs run on schedules and resources are shared—a failed call to an external job board API or data warehouse can trigger thousands of retry attempts across parallel workers, exhausting connection pools and memory before anyone notices.

The pattern has three states: **closed** (normal operation, requests pass through), **open** (failure threshold exceeded, requests rejected immediately), and **half-open** (recovery test, allowing one request to probe if the service is healthy again).

## Practice

**Problem:** Your pipeline ingests job postings from an external API that occasionally returns 503s during maintenance windows. Without protection, your data loader retries aggressively, exhausting your connection pool and blocking other jobs. You need to fail fast and alert, not cascade.

```python
from datetime import datetime, timedelta
from enum import Enum
from typing import Callable, Any
import functools

class CircuitState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"

class CircuitBreaker:
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: int = 60,
        expected_exception: type = Exception,
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.expected_exception = expected_exception
        self.failure_count = 0
        self.last_failure_time = None
        self.state = CircuitState.CLOSED

    def call(self, func: Callable, *args: Any, **kwargs: Any) -> Any:
        if self.state == CircuitState.OPEN:
            if self._should_attempt_reset():
                self.state = CircuitState.HALF_OPEN
            else:
                raise Exception(
                    f"Circuit breaker is OPEN. Retry after "
                    f"{self.recovery_timeout}s"
                )

        try:
            result = func(*args, **kwargs)
            self._on_success()
            return result
        except self.expected_exception as e:
            self._on_failure()
            raise

    def _should_attempt_reset(self) -> bool:
        return (
            self.last_failure_time
            and datetime.now() >= self.last_failure_time + timedelta(
                seconds=self.recovery_timeout
            )
        )

    def _on_success(self) -> None:
        self.failure_count = 0
        self.state = CircuitState.CLOSED

    def _on_failure(self) -> None:
        self.failure_count += 1
        self.last_failure_time = datetime.now()
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitState.OPEN

def circuit_breaker(failure_threshold: int = 5, recovery_timeout: int = 60):
    breaker = CircuitBreaker(failure_threshold, recovery_timeout, Exception)
    
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            return breaker.call(func, *args, **kwargs)
        return wrapper
    
    return decorator

# Usage in a data loader:
@circuit_breaker(failure_threshold=3, recovery_timeout=30)
def fetch_job_postings(api_url: str) -> list[dict]:
    # Simulates external API call; raises on 503
    import requests
    response = requests.get(api_url, timeout=5)
    response.raise_for_status()
    return response.json()

# In your pipeline:
try:
    postings = fetch_job_postings("https://jobs-api.example.com/postings")
except Exception as e:
    print(f"Failed to fetch postings: {e}")
    # Trigger alert, skip this run, don't retry endlessly
```

## Notes

- **Avoid silent failures:** Always log circuit state transitions and alert when breakers trip; silent failures hide systemic issues. Pair with structured logging and metrics (Prometheus counters for state changes).
- **Tune thresholds per dependency:** A flaky internal database might need 10 failures before opening; an external public API might open at 3. Test with chaos engineering or synthetic failures.
- **Half-open probes matter:** A single successful
