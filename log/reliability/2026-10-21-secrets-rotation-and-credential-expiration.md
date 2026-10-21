---
date: 2026-10-21
phase: reliability
topic: Secrets rotation and credential expiration
---

# Secrets rotation and credential expiration

*Quality, reliability and the professional layer*

## Concept

Secrets rotation is the automated or manual process of periodically updating credentials—API keys, database passwords, OAuth tokens—before they expire or are compromised. Without it, a single leaked credential can remain valid indefinitely, and expired credentials cause pipeline failures at unpredictable times. In production data systems, this is the difference between controlled degradation (you know when credentials expire and refresh proactively) and unexpected downtime (a job fails at 2 AM because a key silently expired three days ago).

The practical stakes are high: a data pipeline pulling from a third-party API or writing to a cloud data warehouse depends entirely on valid credentials. If you hardcode credentials in code or store them in a single location without expiration awareness, you're building a time bomb. If you rotate secrets without updating all systems that use them simultaneously, you create cascading failures. The professional approach treats credentials as time-bound resources with explicit ownership: who rotates them, when, how they're distributed, and who monitors expiration.

Credential expiration also forces architectural discipline. You can't rely on "set it once and forget it"—you must monitor, alert, and automate refresh. This surfaces problems early: if your secret rotation process breaks, you find out before credentials actually expire, not after.

## Practice

**Problem:** Your job_postings_fact table is populated nightly from an external recruitment API that requires OAuth token refresh every 90 days. You have three data pipelines (ingestion, transformation, reporting) all using the same token stored in an environment variable. Last month, one pipeline wasn't restarted after a token refresh, causing stale data. How would you implement a solution that ensures all three pipelines use a fresh, valid token?

```sql
-- Store credentials in a secrets table with explicit expiration tracking
CREATE TABLE IF NOT EXISTS pipeline_secrets (
    secret_id INT PRIMARY KEY,
    secret_name VARCHAR(100),
    secret_value VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    rotated_by VARCHAR(100),
    status VARCHAR(20) -- 'active', 'expired', 'revoked'
);

-- Create a view that only returns valid (non-expired) secrets
CREATE VIEW active_secrets AS
SELECT secret_id, secret_name, secret_value
FROM pipeline_secrets
WHERE status = 'active' 
  AND expires_at > CURRENT_TIMESTAMP;

-- In your pipeline code, query the view instead of reading env vars:
-- SELECT secret_value FROM active_secrets WHERE secret_name = 'recruitment_api_token'

-- Monitor expiration: alert when secrets expire in < 7 days
SELECT secret_name, expires_at, 
       DATEDIFF(DAY, CURRENT_TIMESTAMP, expires_at) AS days_until_expiry
FROM pipeline_secrets
WHERE status = 'active'
  AND DATEDIFF(DAY, CURRENT_TIMESTAMP, expires_at) < 7
ORDER BY expires_at ASC;

-- After rotation, mark old secret as expired and insert new one
UPDATE pipeline_secrets 
SET status = 'expired' 
WHERE secret_name = 'recruitment_api_token' 
  AND status = 'active';

INSERT INTO pipeline_secrets (secret_name, secret_value, expires_at, rotated_by, status)
VALUES ('recruitment_api_token', 'new_token_value', 
        DATEADD(DAY, 90, CURRENT_TIMESTAMP), 'automation_user', 'active');
```

## Notes

- **Mistake: Storing secrets in code or config files.** They end up in Git history, logs, and backups. Use a secrets manager (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault) that handles rotation, encryption, and audit trails automatically.
- **Mistake: Rotating credentials without a grace period.** Old systems may still be using them. Overlap the validity of old and new secrets for 1–2 hours, then retire the old one. Always test rotation in staging first.
- **Connection to access control:** Secrets rotation is useless if anyone can read them. Pair it with least-privilege access—each pipeline gets only the credentials it needs, and audit who accessed what.
- **Connection to observability:** Monitor secret access patterns and expiration closely. Set alerts for "secret queried after expiration" or "rotation job failed." Failures here are silent and costly.
- **Worth revisiting:** How do you rotate secrets for systems that can't tolerate downtime? (Answer: blue-green deployments or connection pooling with automatic credential refresh.) Also: how do you handle secrets in local development without weak workarounds?
