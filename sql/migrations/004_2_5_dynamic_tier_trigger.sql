-- Migration 2.4 -> 2.5: Add maintenance_log table and update schema_version, dynamic tier trigger
BEGIN;

-- Add maintenance_log table if missing
CREATE TABLE IF NOT EXISTS maintenance_log (
  id INTEGER PRIMARY KEY,
  action TEXT NOT NULL,
  details_json TEXT,
  duration_ms INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
) STRICT;

-- Update schema_version if behind
UPDATE settings SET value='2.5' WHERE key='schema_version' AND value<'2.5';

INSERT OR IGNORE INTO schema_migrations(version, description)
VALUES ('2.5','Dynamic tier trigger + maintenance log table');

COMMIT;
