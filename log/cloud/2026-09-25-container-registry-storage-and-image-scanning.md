---
date: 2026-09-25
phase: cloud
topic: Container registry storage and image scanning
---

# Container registry storage and image scanning

*Cloud platforms and storage*

## Concept

A container registry stores and versions Docker images centrally (e.g., Docker Hub, ECR, GCR, ACR). Every image layer is stored as a blob; pushing the same base image across teams means storage is deduplicated, but *unused* old tags and intermediate layers accumulate silently. Image scanning analyzes layers for known vulnerabilities (CVEs) at rest—critical because a deployed container image is immutable, so vulnerabilities must be caught before push, not after.

Cost balloons when: (1) you retain every build artifact without cleanup policies, (2) scanning is triggered on every commit rather than on merged code, (3) you push large unoptimized images (fat base layers, build artifacts left in). Without scanning, you deploy known vulnerabilities into production; without storage policies, your registry bill grows unbounded while old images sit unused.

The connection to slow queries: a data pipeline that pulls images from a slow/congested registry or repeatedly downloads large unscanned layers wastes pipeline minutes. Knowing *which* images to pull (by digest, not tag) and *when* they're safe to use directly impacts job scheduling latency.

## Practice

**Problem:** You're tracking data engineering job postings and notice pipeline jobs that build Docker images run much slower on Mondays. You suspect the container registry is the bottleneck. Write a query to identify which job_postings are associated with slow builds, then determine if image pulls are the root cause.

```sql
WITH job_posting_dates AS (
  SELECT 
    job_posted_date,
    EXTRACT(DOW FROM job_posted_date) AS day_of_week,
    COUNT(*) AS posting_count,
    ROUND(AVG(salary_year_avg), 2) AS avg_salary
  FROM job_postings_fact
  GROUP BY job_posted_date, EXTRACT(DOW FROM job_posted_date)
),
monday_analysis AS (
  SELECT 
    day_of_week,
    posting_count,
    avg_salary,
    CASE WHEN day_of_week = 1 THEN 'Monday' 
         WHEN day_of_week = 2 THEN 'Tuesday'
         ELSE 'Other' END AS day_name
  FROM job_posting_dates
)
SELECT 
  day_name,
  posting_count,
  avg_salary,
  ROUND(posting_count / SUM(posting_count) OVER (), 2) AS pct_of_weekly_load
FROM monday_analysis
WHERE day_of_week IN (0, 1, 2)
ORDER BY day_of_week;
```

This baseline shows if data volume (and thus image build load) spikes on Mondays—if so, your registry is under heavy concurrent pull pressure. Next step: check registry logs for layer download latency and enable image layer caching in your CI/CD to reduce redundant pulls.

## Notes

- **Image tag vs. digest:** tags are mutable; always pull by digest in production to guarantee consistency and bypass registry metadata lookups. Tags are convenient for development but costly in high-frequency pipelines.
- **Retention policies are invisible until bill time:** set automatic cleanup rules (delete images older than 90 days or untagged layers) before they accumulate. This is a "set and forget" cost control that often gets skipped.
- **Scanning and policy gates:** scanning finds vulnerabilities but doesn't stop bad images by itself. Pair it with admission controllers (Kubernetes Pod Security Policy, OPA Gatekeeper) to block unsigned or high-severity images from running.
- **Multi-stage builds reduce layer bloat:** a Dockerfile that leaves build dependencies (gcc, npm cache, pip wheels) in the final layer can double image size. `FROM ... AS builder` patterns are mandatory for data pipelines.
- **Registry as a bottleneck in distributed systems:** if your cluster has 50 nodes pulling a 2GB image simultaneously, the registry becomes a single point of contention. Consider local caching (containerd image store) or mirror registries in each availability zone.
