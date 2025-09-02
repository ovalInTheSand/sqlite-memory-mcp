import sqlite3

def test_relationship_same_agent(tools, temp_db):
    with sqlite3.connect(temp_db) as conn:
        conn.execute("INSERT INTO agents(name,kind) VALUES('a1','claude-code')")
        conn.execute("INSERT INTO memory(agent_id, kind, title, body) VALUES (1,'note','m1','b1')")
        conn.execute("INSERT INTO memory(agent_id, kind, title, body) VALUES (1,'note','m2','b2')")
    r = tools.create_memory_relationship(1,2,'builds_on')
    assert r['success']
