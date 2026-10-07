---
date: 2026-10-07
phase: python
topic: Encryption: symmetric vs asymmetric for data at rest
---

# Encryption: symmetric vs asymmetric for data at rest

*Python for data engineering*

## Concept

Symmetric encryption uses a single shared key to encrypt and decrypt data; asymmetric encryption uses a public key to encrypt and a private key to decrypt. For data at rest in pipelines, symmetric is standard because it's fast, deterministic, and suits bulk protection of database tables or parquet files. Asymmetric shines for key distribution and credential handoff—you encrypt a database password with someone's public key, and only they can decrypt it with their private key.

Without encryption, sensitive fields like salary, location, or email expose PII to anyone with filesystem or database access. A data engineer who writes an unencrypted pipeline that lands salary data in S3 has created a compliance violation. Symmetric encryption at rest protects the data lake from casual inspection; asymmetric encryption protects the *keys themselves* during transport and storage.

The practical divide: encrypt the parquet files and database columns symmetrically using AES-256 with a key vault (AWS KMS, Azure Key Vault, HashiCorp Vault). Encrypt the vault credentials asymmetrically when passing them between environments or teams.

## Practice

**Problem:** The `job_postings_fact` table contains `salary_year_avg` and `job_location` fields that are considered sensitive. Write a pipeline step that encrypts these columns at rest in a PostgreSQL database, ensuring the encryption key is rotated safely.

```sql
-- Create encrypted columns
ALTER TABLE job_postings_fact 
ADD COLUMN salary_year_avg_encrypted BYTEA,
ADD COLUMN job_location_encrypted BYTEA;

-- Populate encrypted columns using pgcrypto (symmetric AES-256)
UPDATE job_postings_fact
SET 
  salary_year_avg_encrypted = pgp_sym_encrypt(
    salary_year_avg::TEXT, 
    current_setting('app.encryption_key')
  ),
  job_location_encrypted = pgp_sym_encrypt(
    job_location, 
    current_setting('app.encryption_key')
  );

-- Decrypt on read (for authorized queries only)
SELECT 
  job_id,
  job_title_short,
  pgp_sym_decrypt(salary_year_avg_encrypted::BYTEA, current_setting('app.encryption_key'))::NUMERIC AS salary_year_avg,
  pgp_sym_decrypt(job_location_encrypted::BYTEA, current_setting('app.encryption_key')) AS job_location,
  job_posted_date
FROM job_postings_fact
WHERE job_id = $1;

-- Drop original plaintext columns after verification
ALTER TABLE job_postings_fact DROP COLUMN salary_year_avg, DROP COLUMN job_location;
```

## Notes

- **Key rotation**: Symmetric keys must be rotated periodically; plan for dual-key periods where new writes use the fresh key while old reads still use the retired one. Store key versions in metadata.
- **Searchability vs. security**: Encrypted columns cannot be indexed for fast filtering. Use deterministic encryption (HMAC-based) for fields you must query, or maintain a separate hashed lookup table.
- **Asymmetric for secrets only**: Resist the urge to asymmetrically encrypt bulk data; it's 100–1000× slower. Reserve it for small, high-value secrets like API keys and database passwords.
- **Type safety and validation**: When building Python pipeline code, validate encrypted/decrypted output types strictly—a failed decryption should raise a typed exception, not silently corrupt data.
- **Adjacent: RBAC and column-level security**: Encryption is one layer; pair it with row-level security (RLS) and role-based access control (RBAC) so that even someone with the key cannot read rows outside their scope.
