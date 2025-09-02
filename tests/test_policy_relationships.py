import sqlite3

def test_cross_agent_relationship_denied(tools, temp_db):
    with sqlite3.connect(temp_db) as conn:
        # two different agents
        conn.execute("INSERT INTO agents(name,kind) VALUES('a1','claude-code')")
        conn.execute("INSERT INTO agents(name,kind) VALUES('a2','claude-code')")
        conn.execute("INSERT INTO memory(agent_id, kind, title, body) VALUES (1,'note','m1','b1')")
        conn.execute("INSERT INTO memory(agent_id, kind, title, body) VALUES (2,'note','m2','b2')")
    r = tools.create_memory_relationship(1,2,'builds_on')
    assert not r['success'] and 'policy' in r['error'].lower() or 'disabled' in r['error'].lower()
