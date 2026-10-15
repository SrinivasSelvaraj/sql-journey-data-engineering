---
date: 2026-10-15
phase: cloud
topic: Data transfer costs: ingress free, egress paid model
---

# Data transfer costs: ingress free, egress paid model

*Cloud platforms and storage*

## Concept

Cloud providers charge differently for data movement: ingress (inbound) is typically free, but egress (outbound) incurs significant costs. This asymmetry encourages users to move data *into* cloud platforms cheaply but penalizes extraction, transfer between regions, or downloads. Understanding this model prevents surprise bills and explains why queries sometimes feel "expensive"—you're not paying for computation alone, but for moving terabytes out of the platform.

In practice, egress costs compound quickly. Downloading 1 TB from AWS S3 across regions can cost $20–50; querying the same data *within* the region costs nothing. Similarly, exporting query results, replicating databases across regions, or feeding data to external analytics tools all trigger egress charges. Without awareness, a data pipeline that runs cheaply during development explodes in cost at scale when you start exporting results daily.

This model also shapes architectural decisions: keep transformations inside the cloud, minimize cross-region traffic, and cache results locally rather than re-querying remote sources. Slow queries often aren't slow because of compute—they're slow because you're pulling massive result sets out of the platform instead of aggregating first.

## Practice

**Problem:** You've built a dashboard that queries `job_postings_fact` from a US-East Redshift cluster and sends daily CSV exports to an on-premises analytics server in Europe. The query itself runs in 2 seconds, but dashboards are sluggish and AWS bills are rising. Identify the cost driver and refactor.

```sql
-- BEFORE (expensive): Full export to on-premises
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  job_posted_date, 
  job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
-- Result: 500k rows × 365 days = ~180 GB egress/year @ ~$20/TB = $3,600 cost

-- AFTER (cheaper): Aggregate before export, cache results locally
SELECT 
  job_title_short, 
  job_work_from_home, 
  COUNT(*) as posting_count, 
  AVG(salary_year_avg) as avg_salary,
  MAX(job_posted_date) as latest_posting
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_title_short, job_work_from_home
-- Result: ~500 rows × 365 days = ~2 MB egress/year = ~$0.04 cost
-- Host aggregated results in Europe; sync only deltas.
```

## Notes

- **Mistake:** Assuming query cost = compute cost. A 10-second query on 100 GB of output is cheaper than a 1-second query on 1 TB of egress—egress dominates for data-heavy workloads.
- **Adjacent topic:** Data residency and compliance (GDPR, data sovereignty) reinforce the egress-cost model; moving regulated data out of region is both costly and risky.
- **Revisit:** Understand your cloud provider's egress tiers—AWS offers reduced rates for high-volume egress, and data transfer between services within the same region is often free; this shapes where you place compute.
- **Architecture pattern:** Materialized views and result caching at the edge (CloudFront, local replica DBs) replace egress with cheap intra-region reads; this is why data warehouses encourage "keep queries inside the warehouse."
- **Monitoring:** Set up cost allocation tags per query/pipeline and track bytes egressed; a dashboard that grows from 10 MB/day to 100 MB/day is a cost signal worth investigating before it hits $10k/month.
