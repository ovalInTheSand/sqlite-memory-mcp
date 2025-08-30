#!/usr/bin/env python3
"""
Enhanced MCP Tools for SQLite Memory Management
Provides additional functionality for dynamic schema management and optimization
"""

import sqlite3
import json
import hashlib
import time
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

class SQLiteMemoryTools:
    """Enhanced tools for SQLite memory management via MCP"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
        
    def get_connection(self):
        """Get SQLite connection with proper settings"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        return conn
    
    def log_query_metrics(self, agent_id: int, query: str, execution_time_ms: int, 
                         rows_affected: int = 0, cache_hit: bool = False) -> None:
        """Log query performance metrics"""
        query_hash = hashlib.md5(query.encode()).hexdigest()[:16]
        query_type = query.strip().split()[0].upper()
        
        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO query_metrics 
                (agent_id, query_hash, query_type, execution_time_ms, rows_affected, cache_hit)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (agent_id, query_hash, query_type, execution_time_ms, rows_affected, cache_hit))
    
    def create_agent_table(self, agent_id: int, table_name: str, schema_sql: str, 
                          purpose: str, table_type: str = 'custom') -> Dict[str, Any]:
        """Create a custom table for an agent"""
        with self.get_connection() as conn:
            # Check agent quota
            quota_check = conn.execute("""
                SELECT COUNT(*) as current_count,
                       (SELECT value FROM settings WHERE key = 'max_agent_tables_per_agent') as max_allowed
                FROM agent_tables WHERE agent_id = ?
            """, (agent_id,)).fetchone()
            
            if quota_check['current_count'] >= int(quota_check['max_allowed'] or 10):
                return {"success": False, "error": "Agent table quota exceeded"}
            
            try:
                # Execute the schema SQL
                conn.execute(schema_sql)
                
                # Register the table
                conn.execute("""
                    INSERT INTO agent_tables (table_name, agent_id, purpose, schema_sql, table_type)
                    VALUES (?, ?, ?, ?, ?)
                """, (table_name, agent_id, purpose, schema_sql, table_type))
                
                return {"success": True, "table_name": table_name}
            except sqlite3.Error as e:
                return {"success": False, "error": str(e)}
    
    def track_memory_access(self, memory_id: int) -> None:
        """Track access to a memory entry"""
        with self.get_connection() as conn:
            conn.execute("""
                UPDATE memory 
                SET access_count = access_count + 1,
                    last_accessed = datetime('now')
                WHERE id = ?
            """, (memory_id,))
    
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
        if not (0.0 <= confidence_score <= 1.0):
            return {"success": False, "error": "Confidence score must be between 0.0 and 1.0"}
        
        if not (1 <= weight <= 10):
            return {"success": False, "error": "Weight must be between 1 and 10"}
        
        valid_relationships = ['builds_on', 'contradicts', 'supports', 'obsoletes', 'extends', 'references']
        if relationship_type not in valid_relationships:
            return {"success": False, "error": f"Invalid relationship type. Must be one of: {valid_relationships}"}
        
        try:
            with self.get_connection() as conn:
                conn.execute("""
                    INSERT INTO memory_graph (from_memory_id, to_memory_id, relationship_type, confidence_score, weight)
                    VALUES (?, ?, ?, ?, ?)
                """, (from_memory_id, to_memory_id, relationship_type, confidence_score, weight))
                
                return {"success": True}
        except sqlite3.IntegrityError:
            return {"success": False, "error": "Relationship already exists or memory IDs invalid"}
    
    def archive_old_memories(self, days_threshold: int = 90, access_threshold: int = 3) -> Dict[str, Any]:
        """Archive old, rarely accessed memories"""
        with self.get_connection() as conn:
            # Find candidates
            candidates = conn.execute("""
                SELECT id, title FROM memory 
                WHERE datetime(last_accessed, '+' || ? || ' days') < datetime('now')
                  AND memory_tier != 'archived'
                  AND access_count < ?
            """, (days_threshold, access_threshold)).fetchall()
            
            if not candidates:
                return {"success": True, "archived_count": 0, "message": "No memories eligible for archival"}
            
            # Archive them
            memory_ids = [row['id'] for row in candidates]
            conn.execute(f"""
                UPDATE memory 
                SET memory_tier = 'archived', updated_at = datetime('now')
                WHERE id IN ({','.join(['?'] * len(memory_ids))})
            """, memory_ids)
            
            return {
                "success": True, 
                "archived_count": len(memory_ids),
                "archived_memories": [{"id": row['id'], "title": row['title']} for row in candidates]
            }
    
    def optimize_database(self) -> Dict[str, Any]:
        """Run database optimization"""
        results = {}
        
        with self.get_connection() as conn:
            # Run ANALYZE to update statistics
            start_time = time.time()
            conn.execute("ANALYZE")
            analyze_time = int((time.time() - start_time) * 1000)
            results['analyze_ms'] = analyze_time
            
            # Check for vacuum opportunity
            freelist = conn.execute("PRAGMA freelist_count").fetchone()[0]
            if freelist > 100:
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