# Versioning

Current schema/application schema version: 2.6
Package (Python distribution) version: 0.3.0
Release date: 2025-09-01

### 0.3.0 (Backend Hardening Release - 2025-09-01)
- Package version bumped to 0.3.0 (schema remains 2.6)
- Added BackendConfig with env parsing + value clamping (CACHE_SIZE_KIB, MMAP_SIZE_BYTES, WAL_AUTOCHECKPOINT)
- Immutable read-only mode: clearer errors for missing DB, enforced query_only
- Optional connection pooling (BACKEND_POOL_SIZE) with pool metrics (hits/misses/available)
- Health check method exposing pragma + pool metrics
- Integrity verification toggle (VERIFY_ON_CONNECT=1)
- Structured logging events: backend_config_clamped, invalid_env_int, journal_mode_unexpected, pragma_failed
- Added tests covering clamping, immutable write denial, integrity check, pooling reuse
- Removed duplicate SCHEMA_VERSION definitions & unused imports
- Documentation updated with Upgrade Notes and health_check sample

## Changelog

Planned (next beta target – propose `0.4.0-beta.1` or `1.0.0-beta.1`):
- Add lightweight performance benchmark suite (startup, write throughput, FTS query latency, maintenance ops)
- Publish container image (GHCR) with SBOM + provenance
- Add basic OpenMetrics/Prometheus endpoint (optional) exporting pool + pragma health
- Hardening: enforce minimal file permissions within container (`700` data dir)
- Backup/restore convenience commands in `mem` CLI
- Documentation: benchmarking guide & sizing recommendations

### 2.1 (2025-08-30)
- Removed recursive updated_at triggers (moved timestamp responsibility to application layer)
- Archival trigger now sets memory_tier='archived' instead of 'cold' for consistency
- Added defensive documentation & version file
- Prepared for future retention & write-permission enforcement

### 2.2 (2025-08-30)
- Added schema_migrations tracking table (forward migration safety)
- Introduced retention cleanup command (manage.sh retention) & toolkit method
- Hardened setup: secure perms (chmod 700 dirs, 600 files) & safer settings merge
- Bumped schema_version to 2.2
- No breaking schema field changes

### 2.0 (Initial Enhanced Schema)
- Performance monitoring tables & triggers
- Memory tier system and FTS5 integration

### 2.3 (2025-08-31)
- Partial index on active memories for faster hot read paths
- Opportunistic maintenance scheduler (probabilistic optimize + retention)
- Statement cache scaffolding
- Migration script 002_2_3_quick_wins.sql

### 2.4 (2025-08-31)
- Added dynamic tiering + access decay groundwork (settings keys, migration 003_2_4_dynamic_tiering.sql)
- Future logic will periodically decay access_count and recompute percentile thresholds
- Bumped schema_version to 2.4

### 2.5 (2025-08-30)
- Dynamic tier trigger now reads threshold settings instead of hard-coded values
- Added maintenance_log table (writes for decay & tier recompute forthcoming)
- Bumped schema_version to 2.5 and migration 004_2_5_dynamic_tier_trigger.sql
- Aligns runtime tiering with configurable settings

### 2.6 (2025-08-31)
- Central schema/package version constants exposed via `backend.__init__`
- Correct percentile threshold calculation (use MIN boundary for p90/p60/p30)
- Ceiling-style access decay rounding (preserves low non-zero counts)
- Read-only write gating now dynamic (env var re-read per operation)
- Retention cleanup & relationship/archival operations made transactional
- Enhanced pragma error logging (no silent swallow) with structured warnings
- Relationship policy centralized with clearer duplicate vs FK error messages
- FTS rebuild utility method added
- Test harness loads schema via sqlite3 API (no silent failure via shell)

## Upgrade Guidance
Run the following to apply new archival logic and remove old triggers safely (2.0 -> 2.1):

```
sqlite3 "$CLAUDE_MEMORY_DB" <<'SQL'
-- Remove old touch triggers if they exist
DROP TRIGGER IF EXISTS projects_ut;
DROP TRIGGER IF EXISTS agents_ut;
DROP TRIGGER IF EXISTS memory_ut;
DROP TRIGGER IF EXISTS docs_ut;
-- Ensure archival trigger reflects 2.1
DROP TRIGGER IF EXISTS memory_auto_archive;
.read sql/schema.sql
UPDATE settings SET value='2.1' WHERE key='schema_version';
SQL
```

For quick wins (2.2 -> 2.3):
```
sqlite3 "$CLAUDE_MEMORY_DB" < sql/migrations/002_2_3_quick_wins.sql
```

For dynamic tiering groundwork (2.3 -> 2.4):
```
sqlite3 "$CLAUDE_MEMORY_DB" < sql/migrations/003_2_4_dynamic_tiering.sql
```

Verify:
```
sqlite3 "$CLAUDE_MEMORY_DB" "SELECT value FROM settings WHERE key='schema_version';"
```
