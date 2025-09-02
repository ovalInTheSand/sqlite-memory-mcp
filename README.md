# SQLite Memory MCP: Self-Learning Agent Memory System for Claude Code

**Turn Claude Code into a learning machine** with intelligent memory persistence that remembers everything, learns from patterns, and optimizes itself. Features automatic memory tiering, relationship discovery, performance monitoring, and one-command setup. 

> **Production-Ready:** Self-optimizing SQLite backend 
**Zero-Config:** Interactive setup wizard 
**Smart Analytics:** Performance insights & health monitoring 
**Memory Graph:** Semantic relationship mapping 
**Lightning Fast:** FTS5 search with intelligent caching

## Quick Start

```bash
# One-line (cross‑platform) bootstrap
git clone https://github.com/ovalInTheSand/sqlite-memory-mcp.git && \
cd sqlite-memory-mcp && \
python bootstrap.py --init-db

# (Optional) add dev/test deps & run tests
python bootstrap.py --init-db --dev --run-tests

# Activate virtualenv afterwards (auto‑created .venv)
#   PowerShell: .venv\Scripts\Activate.ps1
#   bash/zsh  : source .venv/bin/activate

# mem CLI examples (after activation)
mem health
mem optimize

# Container alternative (only if you prefer Docker)
docker build -t mem . && mkdir -p data && \
docker run --rm -v $(pwd)/data:/data -e ALLOW_WRITES=1 mem \
  python scripts/deploy_init.py /data/memory.db && \
docker run --rm -v $(pwd)/data:/data mem mem health
```

Your memory system is now ready. The `bootstrap.py` script replaces multiple manual steps (`setup.sh`, manual venv creation, editable install, optional tests) with a single consistent entry point for Windows, WSL, Linux, and macOS. See full details below.

## Table of Contents

- [Quick Start](#quick-start)
- [Key Features](#key-features)
  - [Intelligent Memory Management](#intelligent-memory-management)
  - [Performance & Scalability](#performance--scalability)
  - [Dynamic Agent Schema](#dynamic-agent-schema)
  - [Advanced Analytics](#advanced-analytics)
  - [Ease of Use](#ease-of-use-new)
- [What You Get](#what-you-get)
- [Architecture Overview](#architecture-overview)
  - [Core Tables](#core-tables)
  - [Performance & Monitoring](#performance--monitoring)
  - [Advanced Views](#advanced-views)
- [Configuration](#configuration)
  - [Performance Settings](#performance-settings-configsettingsenv)
  - [MCP Permissions](#mcp-permissions-claudesettingsjson)
- [Usage Examples](#usage-examples)
  - [Basic Memory Operations](#basic-memory-operations)
  - [Memory Relationship Management](#memory-relationship-management)
  - [Agent-Specific Tables](#agent-specific-tables)
  - [Performance Monitoring](#performance-monitoring)
- [Advanced Features](#advanced-features)
  - [Automatic Memory Tiering](#automatic-memory-tiering)
  - [Smart Relationship Discovery](#smart-relationship-discovery)
  - [Performance Optimization](#performance-optimization)
  - [Agent Resource Management](#agent-resource-management)
- [Maintenance & Troubleshooting](#maintenance--troubleshooting)
  - [Database Health Checks](#database-health-checks)
  - [Performance Tuning](#performance-tuning)
  - [Backup & Recovery](#backup--recovery)
- [Monitoring & Analytics](#monitoring--analytics)
- [Code References](#code-references)
  - [Setup Scripts](#setup-scripts)
  - [Configuration Files](#configuration-files)
  - [Python Toolkit](#python-toolkit)
  - [Database Schema](#database-schema)

## **Key Features**

### **Intelligent Memory Management**
- **Multi-tier memory system** (hot/warm/cold/archived) with automatic promotion
- **Memory relationship graph** with confidence scores and semantic linking  
- **Smart access tracking** and usage-based optimization
- **Automatic archival** of old, unused memories

### **Performance & Scalability**
- **SQLite 3.46.0+ optimizations** with automatic PRAGMA optimize
- **Enhanced WAL mode** with autocheckpoint for better concurrency
- **Memory-mapped I/O** (256MB) and intelligent caching (64MB)
- **Query performance monitoring** with metrics and suggestions
- **Backend hardening** with environment value clamping and immutable mode
- **Connection pooling** for reduced overhead (optional, configurable)
- **Health monitoring** with integrity checks and pragma validation

### **Dynamic Agent Schema**
- **Agent-specific tables** without complex migration frameworks
- **Quota management** and usage tracking per agent
- **Simple table creation** with purpose documentation
- **Automatic cleanup** of unused agent resources

### **Advanced Analytics**
- **Database health monitoring** with actionable insights  
- **Performance analytics** per agent and query type
- **Optimization suggestions** with automatic maintenance
- **Resource usage tracking** and capacity planning

### **Ease of Use** (New!)
- **Interactive setup wizard** with guided prompts and validation
- **Comprehensive management tools** for status, config, and maintenance  
- **Automated diagnostics** with fix suggestions and error recovery
- **One-click optimization** and backup with verification
- **Smart defaults** based on system capabilities and usage patterns

## **What You Get**

- **Central configuration**: `config/settings.env` with performance tuning
- **Enhanced STRICT schema** with FTS5, triggers, and intelligent indexing
- **Production-ready SQLite** configuration with WAL, optimization, and monitoring
- **Python toolkit** (`templates/mcp_tools.py`) for advanced operations
- **User/project scope** MCP registration with enhanced permissions
- **One-command installation** with automatic dependency management
- **Versioned schema** (see `VERSION.md`) with documented upgrade path

## Management Commands

```bash
./manage.sh status      # Health dashboard
./manage.sh doctor      # Diagnose & fix
./manage.sh optimize    # Maintenance & tuning
./manage.sh backup      # Verified backups
./manage.sh config      # Interactive settings
```

## Container Usage (Beta)

```bash
docker build -t mem .
mkdir -p data
docker run --rm -v $(pwd)/data:/data -e ALLOW_WRITES=1 mem \
  python scripts/deploy_init.py /data/memory.db
docker run --rm -v $(pwd)/data:/data mem mem health
docker compose up -d   # optional compose service
```

**Done!** Your intelligent memory system is ready.

## **Architecture Overview**

### **Core Tables**
- **`memory`** - Enhanced with access tracking, tier management, relationship support
- **`agents`** - Role-based with memory quotas and performance tracking  
- **`projects`** - Project scoping with resource management
- **`memory_graph`** - Relationship mapping with confidence scores
- **`agent_tables`** - Dynamic schema registry for agent-specific tables

### **Performance & Monitoring**  
- **`query_metrics`** - Query performance analysis and optimization
- **`agent_sessions`** - Session tracking with resource usage
- **`optimization_log`** - Maintenance history and effectiveness tracking

### **Advanced Views**
- **`v_database_health`** - Real-time health metrics and alerts
- **`v_optimization_suggestions`** - AI-driven maintenance recommendations
- **`v_agent_performance`** - Per-agent analytics and resource usage
- **`v_memory_search`** - Enhanced FTS5 search with tier awareness

## **Configuration**

### **Performance Settings** (`config/settings.env`)
```bash
# Database Location
CLAUDE_MEMORY_DB="$HOME/.claude/memory/claude_memory.db"

# Performance Tuning
BUSY_TIMEOUT_MS=30000           # Connection timeout
CACHE_SIZE_KIB=65536           # 64MB cache (clamped: 16 - 524288)
MMAP_SIZE_BYTES=268435456      # 256MB memory mapping (clamped: 1MB - 2GB)
WAL_AUTOCHECKPOINT=1000        # Checkpoint frequency (clamped: 1 - 100000)
BACKEND_POOL_SIZE=0            # Connection pooling (0=disabled, max=small)
VERIFY_ON_CONNECT=0            # Integrity check on connect (1=enabled)

# Memory Management
MEMORY_TIER_PROMOTION_THRESHOLD=50  # Promote after N accesses
MEMORY_ARCHIVAL_DAYS=90            # Archive after N days inactive
MAX_AGENT_TABLES_PER_AGENT=10      # Table quota per agent

# Monitoring
AUTO_OPTIMIZE_ENABLED="1"          # Enable automatic optimization
AUTO_OPTIMIZE_INTERVAL_HOURS=4     # Run optimization every N hours
ENABLE_PERFORMANCE_MONITORING="1"  # Track query performance
```

### **MCP Permissions** (`~/.claude/settings.json`)
```json
{
  "permissions": {
    "allow": [
      "mcp__sqlite_memory__read_query",
      "mcp__sqlite_memory__list_tables", 
      "mcp__sqlite_memory__describe_table",
      "mcp__sqlite_memory__append_insight"
    ]
  },
  "tools": {
    "sqlite_memory": {
      "performance_monitoring": true,
      "auto_optimization": true,
      "memory_tier_management": true,
      "relationship_tracking": true
    }
  }
}
```

## **Usage Examples**

### **Basic Memory Operations**
```sql
-- Store a lesson with automatic tier assignment
INSERT INTO memory (agent_id, kind, title, body, tags_json) VALUES 
(1, 'lesson', 'Always use transactions for multi-step operations', 
 'When doing multiple related database operations, wrap them in a transaction...',
 '["database", "transactions", "best-practices"]');

-- Search memories with FTS5
SELECT m.title, m.memory_tier, snippet
FROM v_memory_search 
WHERE v_memory_search MATCH 'database transactions'
ORDER BY score DESC;
```

### **Memory Relationship Management**
```sql
-- Create relationships between memories
INSERT INTO memory_graph (from_memory_id, to_memory_id, relationship_type, confidence_score)
VALUES (1, 2, 'builds_on', 0.9);

-- View related memories
SELECT from_title, relationship_type, to_title, confidence_score
FROM v_memory_relationships
WHERE from_memory_id = 1;
```

### **Agent-Specific Tables**
```python
# Using the Python toolkit
from templates.mcp_tools import SQLiteMemoryTools

tools = SQLiteMemoryTools(db_path)

# Create custom table for code analysis agent  
result = tools.create_agent_table(
    agent_id=2,
    table_name="agent_2_code_metrics",
    schema_sql="""
        CREATE TABLE agent_2_code_metrics (
            id INTEGER PRIMARY KEY,
            file_path TEXT UNIQUE NOT NULL,
            complexity_score INTEGER,
            test_coverage REAL,
            last_analyzed TEXT DEFAULT (datetime('now'))
        ) STRICT;
    """,
    purpose="Track code quality metrics per file"
)
```

### **Performance Monitoring**
```sql
-- View database health
SELECT * FROM v_database_health;

-- Get optimization suggestions
SELECT suggestion_type, priority, description, action 
FROM v_optimization_suggestions;

-- Agent performance analysis
SELECT agent_name, total_memories, avg_query_time_ms, cache_hit_rate
FROM v_agent_performance
ORDER BY avg_query_time_ms DESC;
```

## **Advanced Features**

### **Backend Hardening & Security**
Enhanced SQLite backend with production-ready safety features:

- **Environment Value Clamping**: Automatically clamps `CACHE_SIZE_KIB` (16-524288), `MMAP_SIZE_BYTES` (1MB-2GB), and `WAL_AUTOCHECKPOINT` (1-100000) to safe ranges with warning logs
- **Immutable Read-Only Mode**: Defense-in-depth when `ALLOW_WRITES=0` - uses SQLite's immutable mode with clear error messages for missing files
- **Connection Pooling**: Optional small connection pool (`BACKEND_POOL_SIZE`) for reduced connection overhead
- **Health Monitoring**: `health_check()` method reports key pragma settings and database status
- **Integrity Verification**: Optional database integrity check on connect (`VERIFY_ON_CONNECT=1`)
- **Structured Logging**: Detailed pragma application logs with mode and path information

### **Upgrade Notes (0.3.0)**
Key changes in 0.3.0 (backend hardening release):

- Added environment value clamping with warnings (`backend_config_clamped`, `invalid_env_int`)
- Immutable read-only mode clarified (friendlier missing DB error)
- Optional connection pooling (`BACKEND_POOL_SIZE`) with pool metrics in `health_check()`
- Integrity verification on connect (`VERIFY_ON_CONNECT=1`)
- Added pool metrics: `pool_hits`, `pool_misses`, `pool_available_read`, `pool_available_write`
- Added `health_check()` for observability

Sample `health_check()` output:
```json
{
  "ok": true,
  "path": "/home/user/.claude/memory/claude_memory.db",
  "foreign_keys": 1,
  "journal_mode": "wal",
  "synchronous": 1,
  "cache_size": -65536,
  "mmap_size": 268435456,
  "wal_autocheckpoint": 1000,
  "pool_size_configured": 4,
  "pool_available_read": 0,
  "pool_available_write": 2,
  "pool_hits": 10,
  "pool_misses": 3
}
```

### **Automatic Memory Tiering**
Memories automatically move between tiers based on access patterns:
- **Hot** (frequently accessed, < 1 day old)
- **Warm** (moderately accessed, recent)  
- **Cold** (rarely accessed, older)
- **Archived** (unused for 90+ days, low access count)

### **Smart Relationship Discovery** 
The system can suggest relationships based on:
- Similar tags or content
- Same project/agent combinations
- Temporal proximity of creation
- Semantic similarity in titles/content

### **Performance Optimization**
- **Automatic ANALYZE** updates query planner statistics
- **Smart VACUUM** reclaims space when fragmentation is detected
- **Index optimization** based on query patterns
- **Memory tier balancing** for optimal performance

### **Agent Resource Management**
- **Table quotas** prevent runaway resource usage
- **Usage tracking** enables cleanup of unused tables
- **Performance monitoring** per agent for optimization
- **Memory budget** management with configurable limits

## **Maintenance & Troubleshooting**

### **Database Health Checks**
```bash
# Check database integrity
sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA integrity_check;"

# View optimization history  
sqlite3 "$CLAUDE_MEMORY_DB" "SELECT * FROM optimization_log ORDER BY executed_at DESC LIMIT 10;"

# Manual optimization
sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA optimize; PRAGMA wal_checkpoint;"

# Dump backend config + health (JSON)
python -m backend.sqlite_backend "$CLAUDE_MEMORY_DB" > backend_health.json

# Safe backup (writes) using VACUUM INTO
python scripts/backup_safe.py "$CLAUDE_MEMORY_DB" "$HOME/.claude/memory/backup_latest.db"
```

### **Performance Tuning**
```bash
# Analyze large tables
sqlite3 "$CLAUDE_MEMORY_DB" "ANALYZE memory; ANALYZE memory_fts;"

# Check for unused space
sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA freelist_count;"

# Manual vacuum if needed
sqlite3 "$CLAUDE_MEMORY_DB" "VACUUM;"
```

### **Backup & Recovery**
```bash
# Hot backup (database can remain active)
sqlite3 "$CLAUDE_MEMORY_DB" ".backup $HOME/.claude/memory/backup_$(date +%Y%m%d).db"

# Restore from backup
cp "$HOME/.claude/memory/backup_20241201.db" "$CLAUDE_MEMORY_DB"
```

## **Monitoring & Analytics**

The system provides comprehensive monitoring through views and the Python toolkit:

- **Real-time health metrics** - Memory usage, query performance, agent activity
- **Performance trends** - Query execution times, cache hit rates, optimization impact  
- **Resource utilization** - Table sizes, index usage, memory consumption
- **Maintenance scheduling** - Automatic optimization based on usage patterns

Use the `templates/mcp_tools.py` toolkit or the installed `mem` CLI for programmatic and shell access to all monitoring and management functions.

## Versioning & Upgrades

Current schema version: see `VERSION.md` (currently 2.6). Package version (PyPI / `pyproject.toml`) may differ from schema version; runtime imports `backend.SCHEMA_VERSION` for authoritative value. Below is the fast‑path example for the earliest upgrade (2.0 -> 2.1); for subsequent versions apply migrations sequentially.

```
sqlite3 "$CLAUDE_MEMORY_DB" <<'SQL'
DROP TRIGGER IF EXISTS projects_ut;
DROP TRIGGER IF EXISTS agents_ut;
DROP TRIGGER IF EXISTS memory_ut;
DROP TRIGGER IF EXISTS docs_ut;
DROP TRIGGER IF EXISTS memory_auto_archive;  -- ensure replacement
.read sql/schema.sql
UPDATE settings SET value='2.1' WHERE key='schema_version'; -- then apply later migrations sequentially
SQL
```

Verify:
```
sqlite3 "$CLAUDE_MEMORY_DB" "SELECT value FROM settings WHERE key='schema_version';"
```

After 2.1, maintain `updated_at` columns in application code (touch triggers removed). For later versions just apply each numbered migration; the consolidated `sql/schema.sql` remains idempotent for fresh installs.

Note: This project intentionally has no external runtime dependencies (stdlib only) for a minimal supply chain surface area.
## **Code References**

### **Setup Scripts**
- [`setup.sh`](./setup.sh) - Interactive one-command setup wizard
- [`manage.sh`](./manage.sh) - Management commands for status, optimization, backup
- [`scripts/install_sqlite_and_mcp.sh`](./scripts/install_sqlite_and_mcp.sh) - SQLite and MCP installation script
- [`scripts/register_user_scope.sh`](./scripts/register_user_scope.sh) - User scope MCP registration
- [`scripts/register_project_scope.sh`](./scripts/register_project_scope.sh) - Project scope MCP registration

### **Configuration Files**
- [`config/settings.env.example`](./config/settings.env.example) - Environment configuration template
- [`config/settings.env`](./config/settings.env) - Active environment configuration
- [`templates/settings.user.sample.json`](./templates/settings.user.sample.json) - Claude settings template

### **Python Toolkit**
- [`templates/mcp_tools.py`](./templates/mcp_tools.py) - Complete Python toolkit for advanced operations
- [`bin/add-sqlite-memory`](./bin/add-sqlite-memory) - CLI tool for MCP server management

### **Database Schema**
- [`sql/schema.sql`](./sql/schema.sql) - Complete database schema with tables, views, and triggers
- [`sql/bootstrap.sql`](./sql/bootstrap.sql) - Initial setup and sample data

### **Documentation**
- [`config/docs/00-overview.md`](./config/docs/00-overview.md) - System architecture overview
- [`config/docs/04-usage.md`](./config/docs/04-usage.md) - Detailed usage examples
- [`config/docs/05-security-backups.md`](./config/docs/05-security-backups.md) - Security and backup procedures
