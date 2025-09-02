#!/usr/bin/env python3
"""
Enhanced MCP Tools for SQLite Memory Management
Provides additional functionality for dynamic schema management and optimization
"""

import sqlite3
import json
import hashlib
import time
import os
import re
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

from backend.sqlite_backend import SQLiteBackend
from backend import SCHEMA_VERSION
from backend.policy import Policy, AgentContext
from backend.logging_util import info, warn, debug

class SQLiteMemoryTools:
    """Enhanced tools for SQLite memory management via MCP.

    Added in v2.1:
      - Optional write gating via env ALLOW_WRITES ("1" enables writes, else read-only)
      - Safer agent table creation (validated table name, single statement)
      - Improved query type detection for WITH CTEs
      - Helper to set updated_at timestamps (since touch triggers removed)
    v2.2: Backend abstraction & immutable read-only mode
    v2.3: Statement cache + probabilistic maintenance scheduler (removed cache later)
    """

    _TABLE_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

    def __init__(self, db_path: str):
        self.db_path = db_path
        self.backend = SQLiteBackend(db_path)
        self._initial_allow = os.environ.get("ALLOW_WRITES", "0") == "1"
        self._maintenance_prob = float(os.environ.get("MAINTENANCE_PROB", "0.01"))
        self.policy = Policy()
        self.metrics_enabled = os.environ.get("ENABLE_PERFORMANCE_MONITORING", "1") == "1"
        self.slow_query_ms = int(os.environ.get("SLOW_QUERY_THRESHOLD_MS", "250"))

    @property
    def allow_writes(self) -> bool:
        # Re-read environment each access to reflect operator changes without re-instantiation
        env_val = os.environ.get("ALLOW_WRITES")
        if env_val is None:
            return self._initial_allow
        return env_val == "1"

    # Statement cache removed (SQLite internal cache suffices; prior cache added little value)

    def maybe_maintain(self):
        """Opportunistic maintenance (optimize + retention) with low overhead."""
        if not self.allow_writes:
            return
        import random
        if random.random() > self._maintenance_prob:
            return
        with self.get_connection() as conn:
            rows = {k: v for k, v in conn.execute(
                "SELECT key, value FROM settings WHERE key IN ('last_optimize_at','last_retention_at','last_decay_at')"
            )}
            now = datetime.utcnow()
            def parse_ts(ts):
                try:
                    return datetime.fromisoformat(ts) if ts else None
                except Exception:
                    return None
            last_opt = parse_ts(rows.get('last_optimize_at'))
            last_ret = parse_ts(rows.get('last_retention_at'))
            last_decay = parse_ts(rows.get('last_decay_at'))
            actions = []
            if not last_opt or (now - last_opt).total_seconds() > 4 * 3600:
                self.optimize_database()
                info("maintenance_optimize", next_hours=4)
                actions.append(('last_optimize_at', now.isoformat()))
            if not last_ret or (now - last_ret).total_seconds() > 6 * 3600:
                self.retention_cleanup()
                info("maintenance_retention", next_hours=6)
                actions.append(('last_retention_at', now.isoformat()))
            if not last_decay or (now - last_decay).total_seconds() > 2 * 3600:
                self.apply_access_decay(conn)
                self.recompute_dynamic_tiers(conn)
                info("maintenance_decay", next_hours=2)
                actions.append(('last_decay_at', now.isoformat()))
            if actions:
                conn.executemany("INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)", actions)

    def get_connection(self):
        return self.backend.connect(write=self.allow_writes)
    
    def log_query_metrics(self, agent_id: int, query: str, execution_time_ms: int,
                          rows_affected: int = 0, cache_hit: bool = False) -> None:
        """Log query performance metrics"""
        if not self.metrics_enabled:
            return
        query_hash = hashlib.md5(query.encode()).hexdigest()[:16]
        # Robust query type detection (handle leading WITH, comments, whitespace)
        stripped = query.strip().lstrip(';')
        # Remove leading SQL comments (simple forms)
        while stripped.startswith('--'):
            stripped = '\n'.join([l for l in stripped.splitlines() if not l.strip().startswith('--')]).strip()
        tokens = stripped.split()
        query_type = tokens[0].upper() if tokens else 'UNKNOWN'
        if query_type == 'WITH':
            # Next meaningful token after CTE(s); simplistic but better than mis-labeling
            for tok in tokens[1:]:
                if tok.rstrip(',').upper() in {"SELECT","INSERT","UPDATE","DELETE","CREATE","DROP"}:
                    query_type = tok.rstrip(',').upper()
                    break
        
        if not self.allow_writes:
            return  # metrics disabled in immutable mode
        try:
            with self.get_connection() as conn:
                conn.execute("""
                    INSERT INTO query_metrics 
                    (agent_id, query_hash, query_type, execution_time_ms, rows_affected, cache_hit)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (agent_id, query_hash, query_type, execution_time_ms, rows_affected, cache_hit))
        except sqlite3.Error as e:
            warn("metrics_insert_failed", error=str(e))
        if execution_time_ms >= self.slow_query_ms:
            warn("slow_query", agent_id=agent_id, ms=execution_time_ms, qtype=query_type)
    
    def _ensure_writable(self) -> Optional[Dict[str, Any]]:
        """Guard to enforce read-only mode when ALLOW_WRITES != 1."""
        if not self.allow_writes:
            return {"success": False, "error": "Writes disabled (set ALLOW_WRITES=1 to enable)"}
        return None

    def create_agent_table(self, agent_id: int, table_name: str, schema_sql: str,
                           purpose: str, table_type: str = 'custom') -> Dict[str, Any]:
        """Create a custom table for an agent.

        Security hardening (v2.1):
          - Validate table name
          - Disallow multiple statements (no embedded semicolons except optional trailing)
          - Enforce write permission
        """
        deny = self._ensure_writable()
        if deny:
            return deny

        if not self._TABLE_NAME_RE.match(table_name):
            return {"success": False, "error": "Invalid table_name"}

        # Normalize schema_sql; require it starts with CREATE TABLE and refers to target table name
        normalized = schema_sql.strip().rstrip(';')
        if ';' in normalized:
            return {"success": False, "error": "Multiple statements not allowed"}
        if f"CREATE TABLE" not in normalized.upper():
            return {"success": False, "error": "Schema must be a CREATE TABLE statement"}
        if table_name.lower() not in normalized.lower():
            return {"success": False, "error": "Schema must create the specified table"}

        with self.get_connection() as conn:
            quota_check = conn.execute("""
                SELECT COUNT(*) as current_count,
                       (SELECT value FROM settings WHERE key = 'max_agent_tables_per_agent') as max_allowed
                FROM agent_tables WHERE agent_id = ?
            """, (agent_id,)).fetchone()
            if quota_check['current_count'] >= int(quota_check['max_allowed'] or 10):
                return {"success": False, "error": "Agent table quota exceeded"}

            try:
                conn.execute("BEGIN")
                agent_ctx = AgentContext(agent_id=agent_id, write_enabled=self.allow_writes)
                if not self.policy.can_write_table(agent_ctx, 'agent_tables', agent_id):
                    conn.execute("ROLLBACK")
                    return {"success": False, "error": "Policy denied table creation"}
                conn.execute(normalized)
                conn.execute("""
                    INSERT INTO agent_tables (table_name, agent_id, purpose, schema_sql, table_type)
                    VALUES (?, ?, ?, ?, ?)
                """, (table_name, agent_id, purpose, normalized, table_type))
                conn.execute("COMMIT")
                return {"success": True, "table_name": table_name}
            except sqlite3.Error as e:
                conn.execute("ROLLBACK")
                return {"success": False, "error": str(e)}
    
    def track_memory_access(self, memory_id: int) -> None:
        """Track access to a memory entry"""
        with self.get_connection() as conn:
            conn.execute(
                """
                UPDATE memory
                SET access_count = access_count + 1,
                    last_accessed = datetime('now')
                WHERE id = ?
                """,
                (memory_id,)
            )
        # Opportunistic maintenance hook (non-blocking if probability low)
        self.maybe_maintain()

    def apply_access_decay(self, conn: Optional[sqlite3.Connection] = None, factor: float = 0.9):
        """Apply multiplicative decay to access_count to prevent unbounded growth.

        factor: remaining proportion after decay (0.9 => reduce by 10%).
        Uses ceiling to keep small counts from vanishing too quickly.
        Only decays rows with access_count > 0.
        """
        if not self.allow_writes:
            return {"success": False, "error": "Writes disabled"}
        close_after = False
        if conn is None:
            conn = self.get_connection()
            close_after = True
        try:
            start = time.time()
            # Ceiling emulation to avoid dropping small non-zero counts to 0 prematurely
            conn.execute(
                "UPDATE memory SET access_count = CASE WHEN access_count > 0 THEN CAST((access_count * ?)+0.9999 AS INTEGER) ELSE access_count END WHERE access_count > 0",
                (factor,)
            )
            dur = int((time.time() - start) * 1000)
            conn.execute(
                "INSERT INTO maintenance_log(action, details_json, duration_ms) VALUES (?,?,?)",
                ('decay', json.dumps({'factor': factor}), dur)
            )
            return {"success": True, "duration_ms": dur}
        finally:
            if close_after:
                conn.close()

    def recompute_dynamic_tiers(self, conn: Optional[sqlite3.Connection] = None):
        """Recompute tier threshold settings based on percentile distribution of access_count.

        Hot threshold = 90th percentile, warm = 60th, cold = 30th (heuristic).
        Stored as integer access_count cutoffs in settings.
        """
        if not self.allow_writes:
            return {"success": False, "error": "Writes disabled"}
        close_after = False
        if conn is None:
            conn = self.get_connection()
            close_after = True
        try:
            rows = conn.execute("""
                WITH ranked AS (
                    SELECT access_count,
                           PERCENT_RANK() OVER (ORDER BY access_count) AS pr
                    FROM memory
                    WHERE memory_tier != 'archived'
                )
                SELECT
                  MIN(CASE WHEN pr >= 0.9 THEN access_count END) AS p90,
                  MIN(CASE WHEN pr >= 0.6 THEN access_count END) AS p60,
                  MIN(CASE WHEN pr >= 0.3 THEN access_count END) AS p30
                FROM ranked
            """).fetchone()
            if rows and any(rows):
                p90 = rows['p90'] or 0
                p60 = rows['p60'] or 0
                p30 = rows['p30'] or 0
                conn.executemany(
                    "INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)",
                    [
                        ('tier_hot_threshold', str(p90)),
                        ('tier_warm_threshold', str(p60)),
                        ('tier_cold_threshold', str(p30))
                    ]
                )
                conn.execute(
                    "INSERT INTO maintenance_log(action, details_json) VALUES (?,?)",
                    ('recompute_tiers', json.dumps({'p90': p90, 'p60': p60, 'p30': p30}))
                )
            return {"success": True, "thresholds": dict(rows) if rows else {} }
        finally:
            if close_after:
                conn.close()

    def touch_updated_at(self, table: str, row_id: int) -> Dict[str, Any]:
        """Update updated_at column (since triggers removed)."""
        if table not in {"projects","agents","memory","docs"}:
            return {"success": False, "error": "Unsupported table"}
        deny = self._ensure_writable()
        if deny:
            return deny
        with self.get_connection() as conn:
            try:
                conn.execute("BEGIN")
                conn.execute(f"UPDATE {table} SET updated_at = datetime('now') WHERE id = ?", (row_id,))
                conn.execute("COMMIT")
                return {"success": True}
            except sqlite3.Error as e:
                conn.execute("ROLLBACK")
                return {"success": False, "error": str(e)}
    
    def get_optimization_suggestions(self) -> List[Dict[str, Any]]:
        """Get optimization suggestions from the database"""
        with self.get_connection() as conn:
            suggestions = conn.execute("""
                SELECT suggestion_type, priority, description, action
                FROM v_optimization_suggestions
                ORDER BY 
                  CASE priority WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END
            """).fetchall()
            
            return [dict(row) for row in suggestions]
    
    def get_database_health(self) -> Dict[str, Any]:
        """Get database health metrics"""
        with self.get_connection() as conn:
            health_data = conn.execute("SELECT * FROM v_database_health").fetchall()
            agent_performance = conn.execute("SELECT * FROM v_agent_performance").fetchall()
            
            return {
                "health_metrics": [dict(row) for row in health_data],
                "agent_performance": [dict(row) for row in agent_performance]
            }
    
    def create_memory_relationship(self, from_memory_id: int, to_memory_id: int,
                                 relationship_type: str, confidence_score: float = 1.0,
                                 weight: int = 1) -> Dict[str, Any]:
        """Create a relationship between memories"""
        deny = self._ensure_writable()
        if deny:
            return deny
        if not (0.0 <= confidence_score <= 1.0):
            return {"success": False, "error": "Confidence score must be between 0.0 and 1.0"}
        
        if not (1 <= weight <= 10):
            return {"success": False, "error": "Weight must be between 1 and 10"}
        
        valid_relationships = ['builds_on', 'contradicts', 'supports', 'obsoletes', 'extends', 'references']
        if relationship_type not in valid_relationships:
            return {"success": False, "error": f"Invalid relationship type. Must be one of: {valid_relationships}"}
        
        try:
            with self.get_connection() as conn:
                row = conn.execute("""
                    SELECT m1.agent_id AS from_agent, m2.agent_id AS to_agent
                    FROM memory m1, memory m2
                    WHERE m1.id = ? AND m2.id = ?
                """, (from_memory_id, to_memory_id)).fetchone()
                if not row:
                    return {"success": False, "error": "One or both memory IDs not found"}
                from_agent, to_agent = row["from_agent"], row["to_agent"]
                # Policy check: centralize cross-agent restriction
                agent_ctx = AgentContext(agent_id=from_agent or to_agent or 0, write_enabled=self.allow_writes)
                if not self.policy.can_create_relationship(agent_ctx, from_agent, to_agent):
                    return {"success": False, "error": "Policy violation: cross-agent relationships not allowed"}
                try:
                    conn.execute("BEGIN")
                    conn.execute("""
                        INSERT INTO memory_graph (from_memory_id, to_memory_id, relationship_type, confidence_score, weight)
                        VALUES (?, ?, ?, ?, ?)
                    """, (from_memory_id, to_memory_id, relationship_type, confidence_score, weight))
                    conn.execute("COMMIT")
                except sqlite3.IntegrityError as ie:
                    conn.execute("ROLLBACK")
                    # Differentiate duplicate vs FK
                    if "UNIQUE" in str(ie).upper() or "PRIMARY KEY" in str(ie).upper():
                        return {"success": False, "error": "Duplicate relationship"}
                    return {"success": False, "error": "Foreign key constraint failed"}
                info("relationship_created", from_id=from_memory_id, to_id=to_memory_id, rel=relationship_type)
                return {"success": True}
        except sqlite3.Error as e:
            return {"success": False, "error": str(e)}
    
    def archive_old_memories(self, days_threshold: int = 90, access_threshold: int = 3) -> Dict[str, Any]:
        """Archive old, rarely accessed memories"""
        deny = self._ensure_writable()
        if deny:
            return deny
        with self.get_connection() as conn:
            candidates = conn.execute("""
                SELECT id, title FROM memory 
                WHERE datetime(last_accessed, '+' || ? || ' days') < datetime('now')
                  AND memory_tier != 'archived'
                  AND access_count < ?
            """, (days_threshold, access_threshold)).fetchall()
            if not candidates:
                return {"success": True, "archived_count": 0, "message": "No memories eligible for archival"}
            memory_ids = [row['id'] for row in candidates]
            placeholders = ','.join(['?'] * len(memory_ids))
            try:
                conn.execute("BEGIN")
                conn.execute(f"UPDATE memory SET memory_tier='archived', updated_at=datetime('now') WHERE id IN ({placeholders})", memory_ids)
                conn.execute("COMMIT")
            except sqlite3.Error as e:
                conn.execute("ROLLBACK")
                return {"success": False, "error": str(e)}
            return {"success": True, "archived_count": len(memory_ids), "archived_memories": [{"id": row['id'], "title": row['title']} for row in candidates]}
    
    def optimize_database(self) -> Dict[str, Any]:
        """Run database optimization (read-safe; VACUUM requires write)."""
        results = {}
        
        with self.get_connection() as conn:
            # Run ANALYZE to update statistics
            start_time = time.time()
            conn.execute("ANALYZE")
            analyze_time = int((time.time() - start_time) * 1000)
            results['analyze_ms'] = analyze_time
            
            # Check for vacuum opportunity
            freelist = conn.execute("PRAGMA freelist_count").fetchone()[0]
            if freelist > 100 and self.allow_writes:
                start_time = time.time()
                conn.execute("VACUUM")
                vacuum_time = int((time.time() - start_time) * 1000)
                results['vacuum_ms'] = vacuum_time
                results['reclaimed_pages'] = freelist
            
            # Run optimize
            conn.execute("PRAGMA optimize")
            
            # Log optimization
            conn.execute("""
                INSERT INTO optimization_log (optimization_type, duration_ms, triggered_by)
                VALUES ('OPTIMIZE', ?, 'mcp_tools')
            """, (analyze_time + results.get('vacuum_ms', 0),))
            
        return {"success": True, "optimization_results": results}

    def retention_cleanup(self) -> Dict[str, Any]:
        """Purge old monitoring data based on retention setting (default 30 days)."""
        deny = self._ensure_writable()
        if deny:
            return deny
        with self.get_connection() as conn:
            try:
                days_row = conn.execute(
                    "SELECT value FROM settings WHERE key='performance_monitoring_retention_days'"
                ).fetchone()
                raw_days = str(days_row[0]).strip() if days_row else "30"
                days = int(raw_days) if raw_days.isdigit() else 30
                cutoff = conn.execute("SELECT datetime('now', ?)", (f'-{days} days',)).fetchone()[0]
                conn.execute("BEGIN")
                qm_deleted = conn.execute(
                    "DELETE FROM query_metrics WHERE created_at < ?", (cutoff,)
                ).rowcount
                opt_deleted = conn.execute(
                    "DELETE FROM optimization_log WHERE executed_at < ?", (cutoff,)
                ).rowcount
                sessions_deleted = conn.execute(
                    "DELETE FROM agent_sessions WHERE last_active < ?", (cutoff,)
                ).rowcount
                conn.execute("COMMIT")
                return {"success": True, "purged": {"query_metrics": qm_deleted, "optimization_log": opt_deleted, "agent_sessions": sessions_deleted, "cutoff": cutoff, "retention_days": days}}
            except sqlite3.Error as e:
                conn.execute("ROLLBACK")
                return {"success": False, "error": str(e)}

    # Maintenance utility: rebuild FTS tables (rarely needed)
    def rebuild_fts(self) -> Dict[str, Any]:
        deny = self._ensure_writable()
        if deny:
            return deny
        with self.get_connection() as conn:
            try:
                conn.execute("INSERT INTO memory_fts(memory_fts) VALUES('rebuild')")
                conn.execute("INSERT INTO doc_fts(doc_fts) VALUES('rebuild')")
                return {"success": True}
            except sqlite3.Error as e:
                return {"success": False, "error": str(e)}

# Example usage functions for MCP server integration
def main():
    """Example usage"""
    import sys
    if len(sys.argv) < 2:
        print("Usage: python mcp_tools.py <db_path>")
        return
    
    tools = SQLiteMemoryTools(sys.argv[1])
    
    # Example: Get database health
    health = tools.get_database_health()
    print("Database Health:")
    print(json.dumps(health, indent=2))
    
    # Example: Get optimization suggestions
    suggestions = tools.get_optimization_suggestions()
    print("\nOptimization Suggestions:")
    print(json.dumps(suggestions, indent=2))

if __name__ == "__main__":
    main()