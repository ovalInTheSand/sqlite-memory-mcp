-- Migration 2.2 -> 2.3 Quick Wins
-- Idempotent: safe to re-run

CREATE INDEX IF NOT EXISTS idx_memory_last_access_active ON memory(last_accessed) WHERE memory_tier!='archived';

INSERT OR IGNORE INTO schema_migrations(version, description)
VALUES ('2.3','Quick wins: partial index + scheduler foundations');

UPDATE settings SET value='2.3' WHERE key='schema_version' AND value<'2.3';
