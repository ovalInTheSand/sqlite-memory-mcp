import sqlite3, time

def test_retention_cleanup(tools, temp_db):
    with sqlite3.connect(temp_db) as conn:
        conn.execute("INSERT OR REPLACE INTO settings(key,value) VALUES('performance_monitoring_retention_days','0')")
        # insert an old optimization_log row by backdating timestamp
        conn.execute("INSERT INTO optimization_log(optimization_type, executed_at) VALUES('ANALYZE', datetime('now','-2 days'))")
    res = tools.retention_cleanup()
    assert res['success']
    purged = res['purged']
    assert purged['optimization_log'] >= 1
