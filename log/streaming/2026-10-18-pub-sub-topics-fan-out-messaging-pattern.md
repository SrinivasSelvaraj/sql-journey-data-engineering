---
date: 2026-10-18
phase: streaming
topic: Pub/Sub topics: fan-out messaging pattern
---

# Pub/Sub topics: fan-out messaging pattern

*Streaming and distributed processing*

## Concept

The fan-out messaging pattern in Pub/Sub systems routes a single message from one topic to multiple consumer applications or downstream topics simultaneously. Rather than having consumers poll a central database or coordinate directly, the publisher emits once and the message broker replicates delivery to all subscribed endpoints in parallel. This decouples producers from consumers and allows independent scaling—one slow consumer doesn't block others.

This matters most when one event triggers multiple independent processing pipelines: a job posting published once must update a search index, trigger email notifications, populate analytics dashboards, and feed a recommendation engine. Without fan-out, you'd either duplicate the publishing logic (brittle and error-prone) or create a bottleneck where all consumers compete for a single queue. The pattern breaks without it because you lose both loose coupling and the ability to add new consumers without redeploying the publisher.

In practice, Pub/Sub systems like Google Cloud Pub/Sub or Apache Kafka handle fan-out natively: one topic with multiple subscriptions (Pub/Sub) or multiple consumer groups (Kafka). Messages are retained or replayed per subscription, so each consumer independently tracks its own offset. Latency and delivery guarantees then become your main design concerns—especially for time-sensitive use cases.

## Practice

**Problem:** A job posting arrives in your system. Three teams need it immediately: the search team needs to index it, the analytics team needs to aggregate salary trends, and the notifications team needs to email matching candidates. Currently you're calling three separate APIs synchronously after each insert, which causes 500ms delays and cascading failures if any service is down.

```sql
-- Publish once to a fan-out topic
PUBLISH TO `projects/my-project/topics/job-postings-published`
  MESSAGE FORMAT JSON AS
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    CURRENT_TIMESTAMP() as event_timestamp
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE();

-- Each consumer team subscribes independently
-- Search team: CREATE SUBSCRIPTION `search-indexer` TOPIC `job-postings-published`
-- Analytics team: CREATE SUBSCRIPTION `salary-aggregator` TOPIC `job-postings-published`
-- Notifications team: CREATE SUBSCRIPTION `candidate-mailer` TOPIC `job-postings-published`

-- Each processes at its own rate without blocking others
```

## Notes

- **Fan-out ≠ broadcast**: Fan-out is *directed* replication to known subscribers; broadcast assumes all listeners are online. In Pub/Sub, subscribers can be created/destroyed dynamically, and messages are buffered if consumers are offline.
- **Common mistake**: Treating subscriptions as queues and sharing one subscription across multiple workers. This causes load-balancing *within* a consumer, not fan-out *across* consumers—use separate subscriptions per downstream system.
- **Delivery guarantees matter**: At-least-once delivery means each subscriber might see duplicates; your consumer logic must be idempotent or you'll corrupt aggregates (e.g., count the same job posting twice).
- **Connects to**: event sourcing (fan-out replays history to new subscribers), change data capture (CDC events fan-out to multiple analytics targets), and choreography-based sagas (multiple services react independently to the same event).
- **Revisit**: How to handle schema evolution when multiple consumers depend on the same topic—versioning strategies and backward compatibility become critical.
