# Enhanced SQLite Memory MCP — Security & Backups

## **🔒 Security Features**

### **Default Security Posture**
- **Read-only MCP tools** by default - writes require explicit permission
- **Agent resource quotas** prevent runaway table creation
- **STRICT mode** tables with comprehensive CHECK constraints
- **Foreign key enforcement** maintains referential integrity
- **Performance monitoring** detects unusual access patterns

### **Database Security Verification**
```sql
-- Verify security settings
PRAGMA foreign_keys;        -- Should be ON (1)
PRAGMA user_version;        -- Should be 2 for enhanced schema  
PRAGMA application_id;      -- Should be 0x434C4D50 ('CLMP')
PRAGMA journal_mode;        -- Should be 'wal'

-- Verify table integrity
PRAGMA integrity_check;     -- Thorough verification
PRAGMA foreign_key_check;   -- Check referential integrity
PRAGMA quick_check;         -- Fast sanity check
```

### **Access Control & Monitoring**
```sql
-- Monitor agent sessions and resource usage
SELECT 
  a.name as agent,
  COUNT(s.id) as active_sessions,
  SUM(s.query_count) as total_queries,
  AVG(s.memory_usage_kb) as avg_memory_kb
FROM agents a
LEFT JOIN agent_sessions s ON a.id = s.agent_id 
WHERE s.last_active >= datetime('now', '-1 hour')
GROUP BY a.id, a.name
ORDER BY total_queries DESC;

-- Check for quota violations or unusual patterns
SELECT * FROM v_agent_table_quotas WHERE quota_status != 'OK';
```

## **💾 Backup Strategies**

### **Hot Backup (Recommended)**
```bash
#!/bin/bash
# Hot backup script - database remains active during backup

BACKUP_DIR="$HOME/.claude/memory/backups"
mkdir -p "$BACKUP_DIR"

# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
sqlite3 "$CLAUDE_MEMORY_DB" ".backup $BACKUP_DIR/claude_memory_$TIMESTAMP.db"

# Verify backup integrity
sqlite3 "$BACKUP_DIR/claude_memory_$TIMESTAMP.db" "PRAGMA integrity_check;" | head -1

echo "✅ Backup completed: $BACKUP_DIR/claude_memory_$TIMESTAMP.db"

# Cleanup old backups (keep last 30 days)
find "$BACKUP_DIR" -name "claude_memory_*.db" -mtime +30 -delete
```

### **WAL-Aware Backup**
```bash
# For maximum consistency, checkpoint WAL first
sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA wal_checkpoint(FULL);"

# Then backup main database file
cp "$CLAUDE_MEMORY_DB" "$BACKUP_DIR/claude_memory_checkpoint_$(date +%Y%m%d).db"

# For complete backup, include WAL and SHM files
cp "$CLAUDE_MEMORY_DB" "$CLAUDE_MEMORY_DB"-wal "$CLAUDE_MEMORY_DB"-shm "$BACKUP_DIR/" 2>/dev/null || true
```

### **Incremental Backup (Python)**
```python
#!/usr/bin/env python3
"""Incremental backup using SQLite's backup API"""

import sqlite3
import os
from datetime import datetime

def incremental_backup(source_db, backup_dir, progress_callback=None):
    """Perform incremental backup with progress reporting"""
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_file = os.path.join(backup_dir, f"claude_memory_incremental_{timestamp}.db")
    
    os.makedirs(backup_dir, exist_ok=True)
    
    source = sqlite3.connect(source_db)
    backup = sqlite3.connect(backup_file)
    
    try:
        # Backup with progress tracking
        def default_progress(status, remaining, total):
            if progress_callback:
                progress_callback(status, remaining, total)
            else:
                percent = ((total - remaining) / total) * 100
                print(f"\rBackup progress: {percent:.1f}% ({total-remaining}/{total} pages)", end='')
        
        source.backup(backup, pages=1000, progress=default_progress)
        print(f"\n✅ Incremental backup completed: {backup_file}")
        
        # Verify backup
        backup.execute("PRAGMA integrity_check").fetchone()
        print("✅ Backup integrity verified")
        
        return backup_file
        
    except Exception as e:
        print(f"❌ Backup failed: {e}")
        if os.path.exists(backup_file):
            os.remove(backup_file)
        raise
    finally:
        backup.close()
        source.close()

# Usage
if __name__ == "__main__":
    import sys
    db_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('CLAUDE_MEMORY_DB')
    backup_dir = sys.argv[2] if len(sys.argv) > 2 else f"{os.path.dirname(db_path)}/backups"
    
    incremental_backup(db_path, backup_dir)
```

## **🔄 Recovery Procedures**

### **Point-in-Time Recovery**
```bash
#!/bin/bash
# Recovery script - restore from backup

BACKUP_FILE="$1"
if [[ -z "$BACKUP_FILE" ]]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

echo "🛑 Stopping MCP server..."
claude mcp remove sqlite_memory || true

echo "📥 Restoring from backup: $BACKUP_FILE"
cp "$BACKUP_FILE" "$CLAUDE_MEMORY_DB"

echo "🔍 Verifying restoration..."
CHECK_RESULT=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA integrity_check;" | head -1)
if [[ "$CHECK_RESULT" == "ok" ]]; then
    echo "✅ Database integrity verified"
else
    echo "❌ Database integrity check failed: $CHECK_RESULT"
    exit 1
fi

echo "📊 Checking data..."
MEMORY_COUNT=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM memory;")
echo "Memory entries: $MEMORY_COUNT"

echo "🚀 Restarting MCP server..."
scripts/register_user_scope.sh

echo "✅ Recovery completed successfully"
```

### **Corruption Recovery**
```bash
# Check for corruption
INTEGRITY_RESULT=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA integrity_check;")
if [[ "$INTEGRITY_RESULT" != "ok" ]]; then
    echo "🚨 Corruption detected: $INTEGRITY_RESULT"
    
    # Attempt recovery to new file
    sqlite3 "$CLAUDE_MEMORY_DB" ".recover ${CLAUDE_MEMORY_DB}.recovered"
    
    # Verify recovered database
    RECOVERED_CHECK=$(sqlite3 "${CLAUDE_MEMORY_DB}.recovered" "PRAGMA integrity_check;" | head -1)
    if [[ "$RECOVERED_CHECK" == "ok" ]]; then
        echo "✅ Recovery successful, replacing original"
        mv "$CLAUDE_MEMORY_DB" "${CLAUDE_MEMORY_DB}.corrupt_backup"
        mv "${CLAUDE_MEMORY_DB}.recovered" "$CLAUDE_MEMORY_DB"
    else
        echo "❌ Recovery failed, restoring from backup"
        # Restore from latest backup
        LATEST_BACKUP=$(ls -t $HOME/.claude/memory/backups/claude_memory_*.db | head -1)
        cp "$LATEST_BACKUP" "$CLAUDE_MEMORY_DB"
    fi
fi
```

## **🏥 Health Monitoring**

### **Automated Health Check Script**
```python
#!/usr/bin/env python3
"""Database health monitoring and alerting"""

from templates.mcp_tools import SQLiteMemoryTools
import sqlite3
import json
import sys
import os
from datetime import datetime

def comprehensive_health_check(db_path):
    """Perform comprehensive health assessment"""
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'database_path': db_path,
        'status': 'OK',
        'checks': {},
        'warnings': [],
        'critical_issues': []
    }
    
    try:
        # Basic connectivity and integrity
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        
        # 1. Integrity check
        integrity_result = conn.execute("PRAGMA integrity_check").fetchone()[0]
        results['checks']['integrity'] = integrity_result == 'ok'
        if integrity_result != 'ok':
            results['critical_issues'].append(f"Database integrity compromised: {integrity_result}")
        
        # 2. Configuration check
        config_checks = {
            'foreign_keys': conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1,
            'journal_mode': conn.execute("PRAGMA journal_mode").fetchone()[0] == 'wal',
            'user_version': conn.execute("PRAGMA user_version").fetchone()[0] == 2
        }
        results['checks'].update(config_checks)
        
        # 3. Size and growth monitoring
        page_count = conn.execute("PRAGMA page_count").fetchone()[0]
        page_size = conn.execute("PRAGMA page_size").fetchone()[0]
        database_size_mb = (page_count * page_size) / (1024 * 1024)
        freelist_count = conn.execute("PRAGMA freelist_count").fetchone()[0]
        
        results['checks']['database_size_mb'] = round(database_size_mb, 2)
        results['checks']['fragmentation_percent'] = round((freelist_count / page_count) * 100, 2)
        
        if database_size_mb > 500:  # 500MB threshold
            results['warnings'].append(f"Large database size: {database_size_mb:.2f} MB")
        
        if freelist_count / page_count > 0.1:  # 10% fragmentation
            results['warnings'].append(f"High fragmentation: {freelist_count} free pages ({(freelist_count/page_count)*100:.1f}%)")
        
        # 4. Memory tier distribution
        tier_stats = conn.execute("""
            SELECT memory_tier, COUNT(*) as count 
            FROM memory 
            GROUP BY memory_tier
        """).fetchall()
        
        total_memories = sum(row[1] for row in tier_stats)
        tier_distribution = {row[0]: row[1] for row in tier_stats}
        results['checks']['memory_distribution'] = tier_distribution
        
        # Check for tier imbalance
        archived_ratio = tier_distribution.get('archived', 0) / max(total_memories, 1)
        if archived_ratio > 0.7:
            results['warnings'].append(f"High archive ratio: {archived_ratio:.1%} of memories are archived")
        
        # 5. Agent resource usage
        agent_stats = conn.execute("""
            SELECT 
                COUNT(DISTINCT a.id) as active_agents,
                COUNT(at.table_name) as custom_tables,
                AVG(at.usage_count) as avg_table_usage
            FROM agents a
            LEFT JOIN agent_tables at ON a.id = at.agent_id
            WHERE a.active = 1
        """).fetchone()
        
        results['checks']['active_agents'] = agent_stats[0]
        results['checks']['custom_tables'] = agent_stats[1] or 0
        results['checks']['avg_table_usage'] = round(agent_stats[2] or 0, 2)
        
        # 6. Recent activity
        recent_activity = conn.execute("""
            SELECT COUNT(*) FROM memory 
            WHERE created_at >= datetime('now', '-24 hours')
        """).fetchone()[0]
        results['checks']['memories_created_24h'] = recent_activity
        
        # 7. Query performance (if available)
        try:
            avg_query_time = conn.execute("""
                SELECT AVG(execution_time_ms) 
                FROM query_metrics 
                WHERE created_at >= datetime('now', '-24 hours')
            """).fetchone()[0]
            
            if avg_query_time:
                results['checks']['avg_query_time_ms'] = round(avg_query_time, 2)
                if avg_query_time > 1000:  # 1 second threshold
                    results['warnings'].append(f"Slow query performance: {avg_query_time:.2f}ms average")
        except:
            pass  # Query metrics may not be available
        
        # Use toolkit for optimization suggestions
        tools = SQLiteMemoryTools(db_path)
        suggestions = tools.get_optimization_suggestions()
        high_priority_suggestions = [s for s in suggestions if s['priority'] == 'High']
        
        if high_priority_suggestions:
            results['critical_issues'].extend([s['description'] for s in high_priority_suggestions])
        
        results['checks']['optimization_suggestions'] = len(suggestions)
        
        # Determine overall status
        if results['critical_issues']:
            results['status'] = 'CRITICAL'
        elif results['warnings']:
            results['status'] = 'WARNING'
        else:
            results['status'] = 'OK'
        
        conn.close()
        
    except Exception as e:
        results['status'] = 'ERROR'
        results['critical_issues'].append(f"Health check failed: {str(e)}")
    
    return results

def main():
    db_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('CLAUDE_MEMORY_DB')
    if not db_path:
        print("Please provide database path or set CLAUDE_MEMORY_DB environment variable")
        sys.exit(1)
    
    health_report = comprehensive_health_check(db_path)
    
    # Output results
    print(json.dumps(health_report, indent=2))
    
    # Exit with appropriate code
    if health_report['status'] == 'CRITICAL':
        sys.exit(2)
    elif health_report['status'] == 'WARNING':
        sys.exit(1)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()
```

### **Performance Monitoring Queries**
```sql
-- Database growth trends
SELECT 
  date(created_at) as date,
  COUNT(*) as memories_created,
  AVG(LENGTH(title) + LENGTH(COALESCE(body, ''))) as avg_memory_size
FROM memory 
WHERE created_at >= date('now', '-30 days')
GROUP BY date(created_at)
ORDER BY date DESC;

-- Memory access patterns
SELECT 
  memory_tier,
  COUNT(*) as count,
  AVG(access_count) as avg_access_count,
  AVG(julianday('now') - julianday(last_accessed)) as avg_days_since_access
FROM memory
GROUP BY memory_tier;

-- Agent activity monitoring  
SELECT 
  a.name,
  COUNT(DISTINCT DATE(s.last_active)) as active_days_last_week,
  SUM(s.query_count) as total_queries,
  AVG(s.memory_usage_kb) as avg_memory_usage_kb
FROM agents a
JOIN agent_sessions s ON a.id = s.agent_id
WHERE s.last_active >= datetime('now', '-7 days')
GROUP BY a.id, a.name
ORDER BY total_queries DESC;

-- Performance bottlenecks
SELECT 
  query_type,
  COUNT(*) as query_count,
  AVG(execution_time_ms) as avg_time,
  MAX(execution_time_ms) as max_time,
  COUNT(CASE WHEN cache_hit = 1 THEN 1 END) * 100.0 / COUNT(*) as cache_hit_rate
FROM query_metrics
WHERE created_at >= datetime('now', '-24 hours')
GROUP BY query_type
HAVING query_count >= 10
ORDER BY avg_time DESC;
```

## **🛡️ Security Best Practices**

### **Regular Maintenance Schedule**
```bash
# Daily health check
0 2 * * * /path/to/health_check.py "$CLAUDE_MEMORY_DB" >> /var/log/claude_memory_health.log

# Weekly optimization
0 3 * * 0 sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA optimize; PRAGMA wal_checkpoint;"

# Monthly backup cleanup  
0 4 1 * * find "$HOME/.claude/memory/backups" -name "*.db" -mtime +90 -delete

# Monthly archive cleanup
0 5 1 * * python3 templates/mcp_tools.py archive_old_memories
```

### **Access Control Verification**
```sql
-- Verify no unauthorized tables exist
SELECT name FROM sqlite_master 
WHERE type = 'table' 
  AND name NOT IN (
    'projects', 'agents', 'memory', 'memory_links', 'memory_graph',
    'tasks', 'runs', 'messages', 'docs', 'doc_chunks', 'settings',
    'agent_tables', 'query_metrics', 'agent_sessions', 'optimization_log'
  )
  AND name NOT LIKE 'agent_%'
  AND name NOT LIKE '%_fts%';

-- Check for suspicious agent activity
SELECT 
  agent_id,
  COUNT(*) as session_count,
  SUM(query_count) as total_queries,
  MAX(query_count) as max_queries_single_session
FROM agent_sessions 
WHERE last_active >= datetime('now', '-24 hours')
GROUP BY agent_id
HAVING total_queries > 10000 OR max_queries_single_session > 1000;
```