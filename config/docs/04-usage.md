# Enhanced SQLite Memory MCP — Usage Guide

## **Basic Memory Operations**

### **Storing Memories**
```sql
-- Store a lesson with automatic categorization
INSERT INTO memory (agent_id, project_id, kind, title, body, tags_json) VALUES 
(1, 1, 'lesson', 'Use indexes for query performance', 
 'Always create indexes on columns used in WHERE clauses...', 
 '["performance", "databases", "optimization"]');

-- Store a decision with high priority
INSERT INTO memory (agent_id, kind, title, body, priority, tags_json) VALUES
(1, 'decision', 'API versioning strategy', 
 'We decided to use semantic versioning for our REST API...', 
 5, '["api", "versioning", "architecture"]');
```

### **Enhanced FTS5 Search**
```sql
-- Full-text search with tier awareness (enhanced)
SELECT m.title, m.memory_tier, m.access_count, snippet
FROM v_memory_search 
WHERE v_memory_search MATCH 'performance optimization'
ORDER BY score DESC
LIMIT 10;

-- Boolean search (OR/AND)
SELECT m.id, m.kind, m.title, m.memory_tier
FROM memory_fts AS f
JOIN memory AS m ON m.id = f.rowid
WHERE f.MATCH 'velocity OR small'
  AND m.memory_tier != 'archived';

-- Prefix wildcard search
SELECT m.id, m.kind, m.title
FROM memory_fts AS f  
JOIN memory AS m ON m.id = f.rowid
WHERE f.MATCH 'pr*';

-- Phrase search
SELECT m.id, m.kind, m.title
FROM memory_fts AS f
JOIN memory AS m ON m.id = f.rowid  
WHERE f.MATCH '"design decision"';

-- Proximity search (NEAR)
SELECT m.id, m.kind, m.title
FROM memory_fts AS f
JOIN memory AS m ON m.id = f.rowid
WHERE f.MATCH 'NEAR("design decision" caching, 5)';

-- Recent lessons with tier filtering
SELECT * FROM v_recent_lessons LIMIT 10;
```

### **Memory Relationships**
```sql
-- Create semantic relationships
INSERT INTO memory_graph (from_memory_id, to_memory_id, relationship_type, confidence_score, weight)
VALUES 
(1, 2, 'builds_on', 0.9, 3),
(3, 1, 'supports', 0.8, 2);

-- View memory relationships  
SELECT * FROM v_memory_relationships WHERE from_memory_id = 1;
```

## **Agent-Specific Operations**

### **Creating Agent Tables**
```python
from templates.mcp_tools import SQLiteMemoryTools

tools = SQLiteMemoryTools(db_path)

# Create performance tracking table
result = tools.create_agent_table(
    agent_id=2,
    table_name="agent_2_performance_logs", 
    schema_sql="""
        CREATE TABLE agent_2_performance_logs (
            id INTEGER PRIMARY KEY,
            operation TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            success BOOLEAN DEFAULT 1,
            metadata_json TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        ) STRICT;
        CREATE INDEX idx_agent_2_perf_op ON agent_2_performance_logs(operation);
    """,
    purpose="Track operation performance metrics"
)
```

### **Managing Agent Resources**
```sql
-- Check agent table quotas
SELECT agent_name, current_tables, max_tables, quota_status
FROM v_agent_table_quotas;

-- View agent performance
SELECT * FROM v_agent_performance WHERE agent_name = 'CodeAnalyzer';

-- Update agent table usage
UPDATE agent_tables SET last_used = datetime('now'), usage_count = usage_count + 1
WHERE table_name = 'agent_2_performance_logs';
```

## **Performance & Monitoring**

### **Database Health Monitoring**
```sql
-- Overall health dashboard
SELECT * FROM v_database_health;

-- Get optimization suggestions  
SELECT suggestion_type, priority, description, action
FROM v_optimization_suggestions
ORDER BY CASE priority WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

-- Query performance analysis (if monitoring enabled)
SELECT agent_name, query_type, avg_execution_time, cache_hit_rate, performance_category
FROM v_query_performance_analysis
WHERE performance_category IN ('SLOW', 'MODERATE');
```

### **Memory Tier Management**
```sql
-- View memory distribution by tier
SELECT memory_tier, COUNT(*) as count, 
       AVG(access_count) as avg_access_count,
       MIN(last_accessed) as oldest_access,
       MAX(last_accessed) as newest_access
FROM memory 
GROUP BY memory_tier;

-- Find memories eligible for promotion
SELECT id, title, access_count, memory_tier, last_accessed
FROM memory 
WHERE memory_tier = 'cold' AND access_count > 25;

-- Find memories eligible for archival
SELECT id, title, access_count, memory_tier, last_accessed
FROM memory
WHERE datetime(last_accessed, '+90 days') < datetime('now')
  AND access_count < 3 
  AND memory_tier != 'archived';
```

### **Maintenance Operations**
```python
# Using the Python toolkit
tools = SQLiteMemoryTools(db_path)

# Get health status
health = tools.get_database_health()
print("Database Health:")
for metric in health['health_metrics']:
    print(f"  {metric['metric']}: {metric['value']}")

# Run optimization
result = tools.optimize_database()
print(f"Optimization completed: {result}")

# Archive old memories
archived = tools.archive_old_memories(days_threshold=90, access_threshold=3)
print(f"Archived {archived['archived_count']} memories")

# Create memory relationships
relationship_result = tools.create_memory_relationship(
    from_memory_id=1, 
    to_memory_id=2,
    relationship_type='builds_on',
    confidence_score=0.8,
    weight=3
)
```

## **Advanced Usage Patterns**

### **Memory Access Tracking**
```python
# Track memory access programmatically (triggers tier management)
tools.track_memory_access(memory_id=123)

# This automatically:
# - Increments access_count
# - Updates last_accessed timestamp  
# - Triggers tier promotion if thresholds are met
```

### **Performance Metrics Logging**
```python
# Log query performance (if monitoring enabled)
tools.log_query_metrics(
    agent_id=1,
    query="SELECT * FROM memory WHERE kind = 'lesson'",
    execution_time_ms=45,
    rows_affected=15,
    cache_hit=True
)
```

### **Complex Queries**
```sql
-- Find highly connected memories
SELECT m.id, m.title, COUNT(mg.to_memory_id) as connection_count
FROM memory m
LEFT JOIN memory_graph mg ON m.id = mg.from_memory_id  
WHERE m.memory_tier != 'archived'
GROUP BY m.id, m.title
HAVING connection_count > 2
ORDER BY connection_count DESC;

-- Search with relationship context
SELECT 
    m1.title as memory_title,
    mg.relationship_type,
    m2.title as related_title,
    mg.confidence_score
FROM memory m1
JOIN memory_graph mg ON m1.id = mg.from_memory_id
JOIN memory m2 ON mg.to_memory_id = m2.id  
WHERE m1.id IN (
    SELECT m.id FROM memory_fts f 
    JOIN memory m ON f.rowid = m.id 
    WHERE f.MATCH 'performance'
);
```

## **Best Practices**

### **Memory Organization**
- Use descriptive **titles** and comprehensive **tags_json** for searchability
- Set appropriate **priority** levels (-10 to 10) for important memories  
- Create **relationships** between related memories for better discovery
- Use **project_id** to scope memories to specific contexts

### **Performance Optimization**  
- Let the system handle **tier management** automatically
- Use **FTS5 search** with v_memory_search view for best performance
- Monitor **query_metrics** to identify slow operations
- Run **optimization suggestions** regularly for maintenance

### **Agent Resource Management**
- Keep agent tables **focused** and **purpose-specific**
- Use **clear naming conventions** (agent_{id}_{purpose})  
- Monitor **usage_count** and clean up unused tables
- Respect **quota limits** to prevent resource exhaustion

### **Search Best Practices**
- Use **tier-aware searches** to exclude archived memories
- Leverage **relationship graph** for contextual discovery
- Combine **FTS5 + SQL filtering** for complex queries
- Use **snippets** from v_memory_search for result previews