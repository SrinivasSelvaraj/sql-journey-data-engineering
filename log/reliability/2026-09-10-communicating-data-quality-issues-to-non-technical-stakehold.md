---
date: 2026-09-10
phase: reliability
topic: Communicating data quality issues to non-technical stakeholders
---

# Communicating data quality issues to non-technical stakeholders

*Quality, reliability and the professional layer*

## Concept

Data quality issues mean nothing to business stakeholders if they're described in technical language. The difference between a junior engineer and a trusted owner is the ability to translate data problems into business impact. When you say "null values in salary_year_avg," a stakeholder hears noise. When you say "we can't reliably rank 30% of our job postings by compensation, which breaks recruiter filtering," they understand why it matters and can make trade-off decisions.

This skill matters most when quality issues force a choice: publish incomplete data, delay a report, or accept a known limitation. Non-technical stakeholders need to understand the scope, severity, and business consequence—not the SQL. They need to know: How many rows are affected? Which business decisions does this break? What's the time/cost to fix versus the cost of working around it?

Without this translation layer, two things fail: first, stakeholders underestimate data risks and make bad decisions based on incomplete information; second, data teams lose credibility because they sound like they're making excuses rather than managing trade-offs professionally.

## Practice

**Problem:** Your job_postings_fact table has 850,000 rows. Salary data is missing for 255,000 rows (30%), but only for remote roles posted in the last 60 days. Your recruitment analytics team wants to publish a report comparing remote vs. office compensation trends. You need to communicate whether this is a blocker.

```sql
-- First, quantify the problem
SELECT 
  job_work_from_home,
  COUNT(*) as total_records,
  COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as missing_salary,
  ROUND(100.0 * COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) / COUNT(*), 1) as pct_missing,
  MIN(job_posted_date) as earliest_affected,
  MAX(job_posted_date) as latest_affected
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 60 DAY
GROUP BY job_work_from_home;

-- Then, frame the business impact
SELECT 
  'Remote roles (last 60 days)' as segment,
  COUNT(*) as records_in_sample,
  COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) as usable_for_salary_analysis,
  ROUND(100.0 * COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) / COUNT(*), 1) as pct_usable
FROM job_postings_fact
WHERE job_work_from_home = TRUE 
  AND job_posted_date >= CURRENT_DATE - INTERVAL 60 DAY;

-- Finally, show the alternative (what the report looks like with the limitation)
SELECT 
  job_work_from_home,
  ROUND(AVG(salary_year_avg), 0) as avg_salary,
  COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) as records_in_calculation
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 60 DAY
GROUP BY job_work_from_home;
```

**Translation for stakeholders:** "We can publish the compensation report, but with a caveat: remote roles in the last 60 days are missing salary data for 30% of postings. This means the remote average is based on ~9,000 salary-complete records instead of ~13,000 total records. The trend is still valid, but less precise for recent remote roles. If precision matters for this report, we recommend either waiting 2 weeks for backfill or excluding the last 60 days."

## Notes

- **Avoid the jargon trap:** Never lead with "null values," "cardinality," or "ETL failures." Lead with the business question: "Can we rank jobs by salary?" Answer: "Only 70% of them, reliably."
- **Quantify before you qualify:** Always know the exact numbers—row counts, percentages, date ranges—before you communicate. Vague quality concerns lose credibility fast.
- **Connect to stakeholder decisions:** Frame every quality issue as a choice, not a catastrophe. "We publish with a limitation" vs. "We delay" vs. "We investigate root cause" are all options worth explaining.
- **This ties to data contracts and SLOs:** Once you communicate data quality professionally, you're ready to formalize expectations—SLOs, data contracts, and alerting thresholds all follow from this skill.
- **Revisit root cause separately:** Telling stakeholders about a problem well is different from fixing it. Don't conflate impact communication with investigation. First tell them what's broken and why it matters; then fix it in parallel.
