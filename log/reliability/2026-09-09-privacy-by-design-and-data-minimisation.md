---
date: 2026-09-09
phase: reliability
topic: Privacy by design and data minimisation
---

# Privacy by design and data minimisation

*Quality, reliability and the professional layer*

## Concept

Privacy by design means embedding data protection into your architecture from day one, not bolting it on later. Data minimisation is the discipline of collecting and storing only what you actually need—no "might be useful someday" fields. Together, they reduce risk (regulatory, reputational, security) and operational cost (smaller tables, fewer retention obligations, simpler audit scope).

This matters most when you own the pipeline end-to-end. A junior engineer might extract every field a source system offers; a trusted owner asks: *Do we need this? Who accesses it? How long do we keep it? What's the cost of a breach?* Without this discipline, you inherit technical debt (bloated schemas), compliance debt (GDPR, CCPA, local laws), and security debt (more data = more surface area).

Breaks without it: You export sensitive fields (SSN, precise coordinates, medical history) you never use. A year later, you discover two engineers have prod access and a third integrated the data with a third-party tool. Now you're scrambling to retract, apologise, and prove you didn't break the law. A trusted owner never gets here.

## Practice

**Problem:** Your `job_postings_fact` table includes `job_location` as precise latitude/longitude coordinates. The analytics team only ever aggregates by state or region. You're storing PII-adjacent data, increasing breach surface area and complicating GDPR deletion requests.

```sql
-- Before: overly granular, risky
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR -- e.g., "40.7128,-74.0060"
);

-- After: minimised, derived when needed
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location_state CHAR(2) -- anonymised, sufficient for analysis
);

-- If precise coordinates are truly needed elsewhere, store in separate, access-controlled table
CREATE TABLE job_postings_location_sensitive (
  job_id INT,
  latitude DECIMAL(10, 6),
  longitude DECIMAL(10, 6),
  -- limited access, automatic purge after 90 days
  created_at TIMESTAMP,
  CONSTRAINT check_purge CHECK (created_at > NOW() - INTERVAL 90 DAY)
);
```

## Notes

- **Confuse minimisation with uselessness.** You still need to solve the business problem; minimisation means removing *redundant* fields, not crippling the pipeline. Ask "what decision does this enable?" If the answer is "none," it goes.
- **Connects to:** data governance (who decides what's "needed"?), retention policies (when do you delete?), access control (who sees what?), and incident response (what do you notify on?).
- **Common mistake:** Assuming privacy is IT/Legal's job. As a data engineer, you're the gatekeeper; you decide what lands in your warehouse. Own it.
- **Revisit retention policies regularly.** A field might have been essential for a feature that no longer exists. Quarterly audits of "why does this column exist?" catch years-old debt.
- **Document your decisions.** Write a line in your schema comments: `job_location_state -- state only; precise coords deleted per retention policy. See wiki/job_posting_privacy.md`. Future you will thank you during an audit.
