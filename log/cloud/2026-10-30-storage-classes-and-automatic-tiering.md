---
date: 2026-10-30
phase: cloud
topic: Storage classes and automatic tiering
---

# Storage classes and automatic tiering

*Cloud platforms and storage*

## Concept

Storage classes define how data is physically stored and accessed in cloud platforms (S3, GCS, Azure Blob), with different cost and retrieval profiles. Hot storage (Standard) costs more to store but offers instant access; cold storage (Glacier, Archive) costs pennies per GB but requires minutes or hours to retrieve. Automatic tiering moves data between classes based on access patterns—frequently accessed objects stay hot, untouched data moves cold automatically.

This matters because **query performance and cost are directly coupled to storage class decisions**. A slow query might be slow because data was moved to cold storage and now requires a restore operation. Conversely, keeping all historical job postings in hot storage when only recent listings are queried wastes thousands monthly. Without tiering rules, you either overpay for access or underpay for retrieval latency and get stuck waiting.

Breaking this means: queries timeout because restoration is pending, cost forecasts are wildly wrong because you didn't account for retrieval fees, or BI tools fail because they can't access archived data within acceptable time windows.

## Practice

**Problem:** Your `job_postings_fact` table grows 50GB monthly. Job analysts query mostly the last 30 days, but compliance requires 7 years of history. You're paying $1,150/month for hot storage alone. Design a tiering strategy.

```sql
-- Set lifecycle rule (pseudo-SQL, actual syntax varies by platform)
ALTER TABLE job_postings_fact
SET LIFECYCLE RULE AS
  TRANSITION TO COOL AFTER 30 DAYS,
  TRANSITION TO COLD AFTER 90 DAYS,
  TRANSITION TO ARCHIVE AFTER 365 DAYS;

-- For retrieval: restore from cold before querying historical compliance data
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_posted_date BETWEEN '2020-01-01' AND '2021-12-31'
  -- This query triggers restore; budget 4–12 hours before results return
```

Expected outcome: ~$50/month for hot (recent), $15/month for cool, <$5/month for archive. Total ~$70/month.

## Notes

- **Mistake:** Assuming all queries are equally latency-sensitive. Batch compliance reports tolerate 12-hour restores; real-time dashboards do not. Separate tables or partitions by access pattern, not just time.
- **Retrieval fees add up.** Pulling 50GB from Glacier costs ~$2.50; do it daily and you've negated storage savings. Monitor restore patterns.
- **Adjacent: partitioning strategies.** Time-based partitions (`job_posted_date`) make tiering at the partition level possible—archive entire months atomically instead of row-by-row.
- **Test restores in lower environments first.** Discovering a 6-hour restore window in production during a critical audit is expensive (in time and reputation).
- **Revisit annually.** Access patterns change; job postings from 2019 might suddenly be queried for research, requiring temporary promotion to hot.
