-- Migration 2.3 -> 2.4: add dynamic tiering / decay tracking keys (idempotent)
INSERT OR IGNORE INTO settings(key,value) VALUES
  ('last_decay_at', NULL),
  ('tier_hot_threshold', 50),
  ('tier_warm_threshold', 20),
  ('tier_cold_threshold', 5);

INSERT OR IGNORE INTO schema_migrations(version, description)
VALUES ('2.4','Dynamic tiering & access decay runtime keys');

UPDATE settings SET value='2.4' WHERE key='schema_version' AND value<'2.4';
