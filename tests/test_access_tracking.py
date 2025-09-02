import sqlite3, time

def test_track_memory_access_increments(tools, temp_db):
    with sqlite3.connect(temp_db) as conn:
        conn.execute("INSERT INTO agents(name,kind) VALUES('a1','claude-code')")
        conn.execute("INSERT INTO memory(agent_id, kind, title, body) VALUES (1,'note','t','b')")
        mid = conn.execute("SELECT id FROM memory").fetchone()[0]
    tools.track_memory_access(mid)
    with sqlite3.connect(temp_db) as conn:
        row = conn.execute("SELECT access_count FROM memory WHERE id=?", (mid,)).fetchone()
        assert row[0] == 1
