import sqlite3

def test_agent_table_quota(tools, temp_db):
    with sqlite3.connect(temp_db) as conn:
        conn.execute("INSERT INTO agents(name,kind) VALUES('a1','claude-code')")
        # set quota to 2 for test
        conn.execute("INSERT OR REPLACE INTO settings(key,value) VALUES('max_agent_tables_per_agent','2')")
    # create two tables
    for i in range(1,3):
        r = tools.create_agent_table(1, f"agent1_tbl{i}", f"CREATE TABLE agent1_tbl{i} (id INTEGER PRIMARY KEY) STRICT", f"t{i}")
        assert r['success']
    # third should fail
    r3 = tools.create_agent_table(1, "agent1_tbl3", "CREATE TABLE agent1_tbl3 (id INTEGER PRIMARY KEY) STRICT", "t3")
    assert not r3['success']
