import os, sqlite3, tempfile, pytest
from templates.mcp_tools import SQLiteMemoryTools

@pytest.fixture()
def ro_tools(temp_db, monkeypatch):
    monkeypatch.setenv('ALLOW_WRITES','0')
    return SQLiteMemoryTools(temp_db)

def test_relationship_denied_read_only(ro_tools, temp_db):
    with sqlite3.connect(temp_db) as conn:
        conn.execute("INSERT INTO agents(name,kind) VALUES('a1','claude-code')")
        conn.execute("INSERT INTO memory(agent_id, kind, title, body) VALUES (1,'note','m1','b1')")
        conn.execute("INSERT INTO memory(agent_id, kind, title, body) VALUES (1,'note','m2','b2')")
    r = ro_tools.create_memory_relationship(1,2,'builds_on')
    assert not r['success'] and 'disabled' in r['error'].lower()
