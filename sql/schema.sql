-- Schema Version: 2.5 (2025-08-30)
-- 2.3 -> 2.4 (Dynamic Tiering & Decay):
--   * Introduce dynamic access decay & adaptive tier recalibration (code-driven)
--   * No structural changes; version bump for coordinated runtime logic
--   * Migration adds tracking keys only if missing
CREATE TABLE IF NOT EXISTS projects (
  id           INTEGER PRIMARY KEY,
  slug         TEXT NOT NULL UNIQUE,
  name         TEXT NOT NULL,
  description  TEXT,
  repo_url     TEXT,
  root_path    TEXT,
  status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived')),
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  created_date TEXT GENERATED ALWAYS AS (date(created_at)) VIRTUAL
) STRICT;

CREATE TABLE IF NOT EXISTS agents (
  id           INTEGER PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,
  kind         TEXT NOT NULL CHECK (kind IN ('claude-code','subagent','other')),
  active       INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
  persona_json TEXT,
  tools_json   TEXT,
  memory_quota_mb INTEGER DEFAULT 100 CHECK (memory_quota_mb > 0),
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  created_date TEXT GENERATED ALWAYS AS (date(created_at)) VIRTUAL
) STRICT;

CREATE TABLE IF NOT EXISTS memory (
  id            INTEGER PRIMARY KEY,
  project_id    INTEGER REFERENCES projects(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  agent_id      INTEGER REFERENCES agents(id)   ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  kind          TEXT NOT NULL CHECK (kind IN ('note','lesson','decision','task','snippet','doc','link','event')),
  title         TEXT NOT NULL,
  body          TEXT,
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','in_progress','done','archived')),
  priority      INTEGER NOT NULL DEFAULT 0 CHECK (priority BETWEEN -10 AND 10),
  access_count  INTEGER NOT NULL DEFAULT 0,
  last_accessed TEXT DEFAULT (datetime('now')),
  memory_tier   TEXT NOT NULL DEFAULT 'hot' CHECK (memory_tier IN ('hot','warm','cold','archived')),
  tags_json     TEXT,
  tags_text     TEXT,  -- denormalized by triggers
  refs_json     TEXT,
  meta_json     TEXT,
  source        TEXT NOT NULL DEFAULT 'manual',
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  created_date  TEXT GENERATED ALWAYS AS (date(created_at)) VIRTUAL
) STRICT;

CREATE TABLE IF NOT EXISTS memory_links (
  from_id  INTEGER NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
  to_id    INTEGER NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
  relation TEXT NOT NULL CHECK (relation IN ('relates_to','duplicates','supersedes','depends_on','blocks')),
  PRIMARY KEY (from_id, to_id, relation)
) WITHOUT ROWID, STRICT;

CREATE TABLE IF NOT EXISTS tasks (
  id             INTEGER PRIMARY KEY,
  project_id     INTEGER REFERENCES projects(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  agent_id       INTEGER REFERENCES agents(id)   ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  title          TEXT NOT NULL,
  description    TEXT,
  status         TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','blocked','done','archived')),
  priority       INTEGER NOT NULL DEFAULT 0 CHECK (priority BETWEEN -10 AND 10),
  due_at         TEXT,
  parent_task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  created_at     TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at     TEXT NOT NULL DEFAULT (datetime('now')),
  due_date       TEXT GENERATED ALWAYS AS (date(due_at)) VIRTUAL,
  created_date   TEXT GENERATED ALWAYS AS (date(created_at)) VIRTUAL
) STRICT;

CREATE TABLE IF NOT EXISTS runs (
  id            INTEGER PRIMARY KEY,
  project_id    INTEGER REFERENCES projects(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  agent_id      INTEGER REFERENCES agents(id)   ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  tool_name     TEXT NOT NULL,
  input_text    TEXT,
  output_text   TEXT,
  metrics_json  TEXT,
  status        TEXT NOT NULL DEFAULT 'ok' CHECK (status IN ('ok','error')),
  started_at    TEXT NOT NULL DEFAULT (datetime('now')),
  finished_at   TEXT
) STRICT;

CREATE TABLE IF NOT EXISTS messages (
  id            INTEGER PRIMARY KEY,
  run_id        INTEGER REFERENCES runs(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
  role          TEXT NOT NULL CHECK (role IN ('system','user','assistant','tool')),
  content       TEXT NOT NULL,
  meta_json     TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  created_date  TEXT GENERATED ALWAYS AS (date(created_at)) VIRTUAL
) STRICT;

CREATE TABLE IF NOT EXISTS docs (
  id           INTEGER PRIMARY KEY,
  project_id   INTEGER REFERENCES projects(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  uri          TEXT,
  title        TEXT,
  mime         TEXT,
  checksum     TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  created_date TEXT GENERATED ALWAYS AS (date(created_at)) VIRTUAL
) STRICT;

CREATE TABLE IF NOT EXISTS doc_chunks (
  id         INTEGER PRIMARY KEY,
  doc_id     INTEGER NOT NULL REFERENCES docs(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
  chunk_idx  INTEGER NOT NULL,
  content    TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (doc_id, chunk_idx)
) STRICT;

CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value ANY
) STRICT;

-- =============== DYNAMIC AGENT TABLES ===============
CREATE TABLE IF NOT EXISTS agent_tables (
  table_name TEXT PRIMARY KEY,
  agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  purpose TEXT NOT NULL,
  schema_sql TEXT NOT NULL,
  table_type TEXT NOT NULL DEFAULT 'custom' CHECK (table_type IN ('custom','temp','view')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used TEXT DEFAULT (datetime('now')),
  usage_count INTEGER DEFAULT 0
) STRICT;

-- =============== MEMORY RELATIONSHIP GRAPH ===============
CREATE TABLE IF NOT EXISTS memory_graph (
  from_memory_id INTEGER NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
  to_memory_id INTEGER NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
  relationship_type TEXT NOT NULL CHECK (relationship_type IN (
    'builds_on', 'contradicts', 'supports', 'obsoletes', 'extends', 'references'
  )),
  confidence_score REAL NOT NULL DEFAULT 1.0 CHECK (confidence_score BETWEEN 0.0 AND 1.0),
  weight INTEGER NOT NULL DEFAULT 1 CHECK (weight BETWEEN 1 AND 10),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT DEFAULT 'system',
  PRIMARY KEY (from_memory_id, to_memory_id, relationship_type)
) WITHOUT ROWID, STRICT;

-- =============== PERFORMANCE MONITORING ===============
CREATE TABLE IF NOT EXISTS query_metrics (
  id INTEGER PRIMARY KEY,
  agent_id INTEGER REFERENCES agents(id) ON DELETE SET NULL,
  query_hash TEXT NOT NULL,
  query_type TEXT CHECK (query_type IN ('SELECT','INSERT','UPDATE','DELETE','CREATE','DROP')),
  execution_time_ms INTEGER NOT NULL,
  rows_affected INTEGER DEFAULT 0,
  cache_hit INTEGER DEFAULT 0 CHECK (cache_hit IN (0,1)),
  table_scans INTEGER DEFAULT 0,
  index_uses INTEGER DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
) STRICT;

CREATE TABLE IF NOT EXISTS agent_sessions (
  id INTEGER PRIMARY KEY,
  agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  connection_id TEXT UNIQUE NOT NULL,
  last_active TEXT NOT NULL DEFAULT (datetime('now')),
  read_locks INTEGER NOT NULL DEFAULT 0,
  write_locks INTEGER NOT NULL DEFAULT 0,
  memory_usage_kb INTEGER DEFAULT 0,
  query_count INTEGER DEFAULT 0
) STRICT;

CREATE TABLE IF NOT EXISTS optimization_log (
  id INTEGER PRIMARY KEY,
  optimization_type TEXT NOT NULL CHECK (optimization_type IN ('ANALYZE','OPTIMIZE','VACUUM','REINDEX')),
  target_table TEXT,
  duration_ms INTEGER,
  before_size_bytes INTEGER,
  after_size_bytes INTEGER,
  improvement_factor REAL,
  triggered_by TEXT DEFAULT 'automatic',
  executed_at TEXT NOT NULL DEFAULT (datetime('now'))
) STRICT;

-- NOTE: Base schema reflects latest version (2.6). Earlier versions should apply migrations sequentially.
CREATE INDEX IF NOT EXISTS idx_memory_proj_kind        ON memory(project_id, kind);
CREATE INDEX IF NOT EXISTS idx_memory_status           ON memory(status);
CREATE INDEX IF NOT EXISTS idx_memory_priority_recent  ON memory(status, priority DESC, created_at);
CREATE INDEX IF NOT EXISTS idx_memory_created_date     ON memory(created_date);
CREATE INDEX IF NOT EXISTS idx_memory_tier_access      ON memory(memory_tier, last_accessed);
CREATE INDEX IF NOT EXISTS idx_memory_access_count     ON memory(access_count DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_open              ON tasks(status) WHERE status IN ('open','in_progress','blocked');
CREATE INDEX IF NOT EXISTS idx_tasks_due_sort          ON tasks(status, due_date, priority DESC);
CREATE INDEX IF NOT EXISTS idx_runs_agent_time         ON runs(agent_id, started_at);
CREATE INDEX IF NOT EXISTS idx_messages_run_time       ON messages(run_id, created_at);
CREATE INDEX IF NOT EXISTS idx_memory_graph_from       ON memory_graph(from_memory_id);
CREATE INDEX IF NOT EXISTS idx_memory_graph_to         ON memory_graph(to_memory_id);
CREATE INDEX IF NOT EXISTS idx_memory_graph_type       ON memory_graph(relationship_type);
CREATE INDEX IF NOT EXISTS idx_query_metrics_agent     ON query_metrics(agent_id, created_at);
CREATE INDEX IF NOT EXISTS idx_query_metrics_hash      ON query_metrics(query_hash);
CREATE INDEX IF NOT EXISTS idx_agent_sessions_active   ON agent_sessions(last_active);
CREATE INDEX IF NOT EXISTS idx_optimization_log_time   ON optimization_log(executed_at);
CREATE INDEX IF NOT EXISTS idx_agent_tables_agent      ON agent_tables(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_tables_used       ON agent_tables(last_used);
-- Quick Win 2.3: partial index focused on active (non-archived) memories by recency
CREATE INDEX IF NOT EXISTS idx_memory_last_access_active ON memory(last_accessed) WHERE memory_tier!='archived';
-- 2.6: Composite indexes to accelerate relationship queries by (from,type) and (to,type)
CREATE INDEX IF NOT EXISTS idx_memory_graph_from_type  ON memory_graph(from_memory_id, relationship_type);
CREATE INDEX IF NOT EXISTS idx_memory_graph_to_type    ON memory_graph(to_memory_id, relationship_type);

-- =============== JSON HELPERS ===============
CREATE VIEW IF NOT EXISTS v_memory_tags AS
SELECT m.id AS memory_id,
       lower(value) AS tag
FROM memory AS m, json_each(m.tags_json)
WHERE json_valid(m.tags_json);

-- =============== FTS5 (EXTERNAL-CONTENT) ===============
CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
  title, body, tags,
  content='memory', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2 tokenchars ''-_@.#''',
  prefix='2 3'
);

-- =============== ENHANCED TRIGGERS ===============
-- Memory access tracking and tier management
-- Dynamic threshold tier trigger (uses settings values; fallback to defaults if missing)
CREATE TRIGGER IF NOT EXISTS memory_access_tracker
AFTER UPDATE OF access_count, last_accessed ON memory
WHEN NEW.access_count != OLD.access_count AND NEW.memory_tier != 'archived'
BEGIN
  UPDATE memory
  SET memory_tier = (
    CASE
      WHEN NEW.access_count >= COALESCE((SELECT CAST(value AS INTEGER) FROM settings WHERE key='tier_hot_threshold'),50) THEN 'hot'
      WHEN NEW.access_count >= COALESCE((SELECT CAST(value AS INTEGER) FROM settings WHERE key='tier_warm_threshold'),20) THEN 'warm'
      WHEN NEW.access_count >= COALESCE((SELECT CAST(value AS INTEGER) FROM settings WHERE key='tier_cold_threshold'),5) THEN 'cold'
      ELSE memory_tier
    END
  )
  WHERE id = NEW.id;
END;

-- Automatic archival (previously set to 'cold'); ensures rarely accessed, old memories move to archived tier
CREATE TRIGGER IF NOT EXISTS memory_auto_archive
AFTER UPDATE OF last_accessed ON memory
WHEN datetime(NEW.last_accessed, '+90 days') < datetime('now')
  AND NEW.memory_tier != 'archived'
  AND NEW.access_count < 5
BEGIN
  UPDATE memory 
  SET memory_tier = 'archived'
  WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS memory_ai AFTER INSERT ON memory BEGIN
  UPDATE memory SET tags_text = COALESCE((SELECT group_concat(value,' ')
                                          FROM json_each(new.tags_json)), '')
  WHERE id = new.id;
  INSERT INTO memory_fts(rowid,title,body,tags)
  VALUES (new.id, new.title, new.body, COALESCE((SELECT group_concat(value,' ')
                                                 FROM json_each(new.tags_json)), ''));
END;

CREATE TRIGGER IF NOT EXISTS memory_au AFTER UPDATE OF title, body, tags_json ON memory BEGIN
  UPDATE memory SET tags_text = COALESCE((SELECT group_concat(value,' ')
                                          FROM json_each(new.tags_json)), '')
  WHERE id = new.id;
  INSERT INTO memory_fts(memory_fts, rowid) VALUES('delete', old.id);
  INSERT INTO memory_fts(rowid,title,body,tags)
  VALUES (new.id, new.title, new.body, COALESCE((SELECT group_concat(value,' ')
                                                 FROM json_each(new.tags_json)), ''));
END;

CREATE TRIGGER IF NOT EXISTS memory_ad AFTER DELETE ON memory BEGIN
  INSERT INTO memory_fts(memory_fts, rowid) VALUES('delete', old.id);
END;

-- Doc FTS
CREATE VIRTUAL TABLE IF NOT EXISTS doc_fts USING fts5(
  content,
  content='doc_chunks', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2 tokenchars ''-_@.#''',
  prefix='2 3'
);

CREATE TRIGGER IF NOT EXISTS doc_chunks_ai AFTER INSERT ON doc_chunks
BEGIN INSERT INTO doc_fts(rowid, content) VALUES (new.id, new.content); END;

CREATE TRIGGER IF NOT EXISTS doc_chunks_au AFTER UPDATE OF content ON doc_chunks
BEGIN
  INSERT INTO doc_fts(doc_fts, rowid) VALUES('delete', old.id);
  INSERT INTO doc_fts(rowid, content) VALUES (new.id, new.content);
END;

CREATE TRIGGER IF NOT EXISTS doc_chunks_ad AFTER DELETE ON doc_chunks
BEGIN INSERT INTO doc_fts(doc_fts, rowid) VALUES('delete', old.id); END;

-- =============== ENHANCED VIEWS FOR MCP TOOLS ===============
CREATE VIEW IF NOT EXISTS v_recent_lessons AS
SELECT id, project_id, title, substr(body,1,280) AS preview, created_at
FROM memory
WHERE kind='lesson' AND memory_tier IN ('hot','warm')
ORDER BY datetime(created_at) DESC;

CREATE VIEW IF NOT EXISTS v_memory_search AS
SELECT m.id, m.project_id, m.kind, m.title,
       snippet(memory_fts, 1, '<b>','</b>','…', 10) AS snippet,
       bm25(memory_fts) AS score,
       m.memory_tier, m.access_count
FROM memory_fts
JOIN memory AS m ON m.id = memory_fts.rowid
WHERE m.memory_tier != 'archived';

CREATE VIEW IF NOT EXISTS v_open_tasks AS
SELECT * FROM tasks
WHERE status IN ('open','in_progress','blocked')
ORDER BY CASE status WHEN 'blocked' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END,
         priority DESC, IFNULL(due_at,'9999-12-31');

-- Agent performance and schema management views
CREATE VIEW IF NOT EXISTS v_agent_performance AS
SELECT 
  a.name, a.kind,
  COUNT(DISTINCT m.id) AS total_memories,
  COUNT(DISTINCT qm.id) AS total_queries,
  AVG(qm.execution_time_ms) AS avg_query_time_ms,
  SUM(CASE WHEN qm.cache_hit = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(qm.id), 0) AS cache_hit_rate
FROM agents a
LEFT JOIN memory m ON a.id = m.agent_id
LEFT JOIN query_metrics qm ON a.id = qm.agent_id
WHERE a.active = 1
GROUP BY a.id, a.name, a.kind;

CREATE VIEW IF NOT EXISTS v_optimization_suggestions AS
SELECT 
  'VACUUM' AS suggestion_type, 'High' AS priority,
  'Reclaim ' || (SELECT * FROM pragma_freelist_count()) || ' unused pages' AS description,
  'VACUUM;' AS action
WHERE (SELECT * FROM pragma_freelist_count()) > 100
UNION ALL
SELECT 
  'MEMORY_ARCHIVAL', 'Medium',
  'Archive ' || COUNT(*) || ' old memories', 
  'UPDATE memory SET memory_tier = ''archived'' WHERE last_accessed < datetime(''now'', ''-90 days'')'
FROM memory 
WHERE datetime(last_accessed, '+90 days') < datetime('now') AND memory_tier != 'archived' AND access_count < 3
HAVING COUNT(*) > 0
UNION ALL
SELECT 
  'ANALYZE', 'Low',
  'Update query planner statistics',
  'ANALYZE;'
WHERE NOT EXISTS (SELECT 1 FROM optimization_log WHERE optimization_type = 'ANALYZE' AND executed_at > datetime('now', '-1 day'));

CREATE VIEW IF NOT EXISTS v_database_health AS
SELECT 'total_memories' AS metric, COUNT(*) AS value FROM memory
UNION ALL
SELECT 'hot_memories', COUNT(*) FROM memory WHERE memory_tier = 'hot'
UNION ALL
SELECT 'archived_memories', COUNT(*) FROM memory WHERE memory_tier = 'archived'
UNION ALL
SELECT 'active_agents', COUNT(*) FROM agents WHERE active = 1
UNION ALL
SELECT 'avg_query_time_24h', CAST(AVG(execution_time_ms) AS INTEGER) 
FROM query_metrics WHERE created_at >= datetime('now', '-24 hours');

-- =============== TOUCH TRIGGERS ===============
-- Removed recursive touch triggers in v2.1. Maintain updated_at in application layer.

-- =============== INITIALIZATION & SETTINGS ===============
INSERT OR IGNORE INTO settings (key, value) VALUES 
  ('schema_version', '2.6'),
  ('auto_optimize_enabled', 1),
  ('auto_optimize_interval_hours', 4),
  ('memory_tier_promotion_threshold', 50),
  ('memory_archival_days', 90),
  ('max_agent_tables_per_agent', 10),
  ('performance_monitoring_retention_days', 30);

-- Migration tracking (introduced in 2.2)
CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT (datetime('now')),
  description TEXT
) STRICT;

INSERT OR IGNORE INTO schema_migrations(version, description) VALUES
  ('2.2', 'Introduce schema_migrations tracking table'),
  ('2.3', 'Quick wins: partial index + scheduler foundations'),
  ('2.4', 'Dynamic tiering & access decay (runtime logic)'),
  ('2.5', 'Dynamic tier trigger + maintenance log table'),
  ('2.6', 'Composite relationship indexes + logging infra');

-- Maintenance log (new in 2.5)
CREATE TABLE IF NOT EXISTS maintenance_log (
  id INTEGER PRIMARY KEY,
  action TEXT NOT NULL,
  details_json TEXT,
  duration_ms INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
) STRICT;

PRAGMA optimize;

-- Safety cleanup (ensure old recursive touch triggers gone even if lingering from pre-2.1 versions)
DROP TRIGGER IF EXISTS projects_ut;
DROP TRIGGER IF EXISTS agents_ut;
DROP TRIGGER IF EXISTS memory_ut;
DROP TRIGGER IF EXISTS docs_ut;
