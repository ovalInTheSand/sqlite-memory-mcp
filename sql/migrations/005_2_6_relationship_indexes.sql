-- Migration 2.5 -> 2.6: Composite relationship indexes + schema_version bump
BEGIN;
CREATE INDEX IF NOT EXISTS idx_memory_graph_from_type  ON memory_graph(from_memory_id, relationship_type);
CREATE INDEX IF NOT EXISTS idx_memory_graph_to_type    ON memory_graph(to_memory_id, relationship_type);
UPDATE settings SET value='2.6' WHERE key='schema_version' AND value<'2.6';
INSERT OR IGNORE INTO schema_migrations(version, description) VALUES('2.6','Composite relationship indexes + logging infra');
COMMIT;
