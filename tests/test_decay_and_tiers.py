import sqlite3, json
from templates.mcp_tools import SQLiteMemoryTools

def seed_memories(conn, counts):
    for i,c in enumerate(counts, start=1):
        conn.execute("INSERT INTO memory(agent_id, kind, title, body, access_count) VALUES (1,'note',?, ?, ?)", (f'Title {i}','Body', c))

def test_decay_and_tier_recompute(tools, temp_db):
    with sqlite3.connect(temp_db) as conn:
        seed_memories(conn, [1,5,10,20,40,80])
    with tools.get_connection() as conn:
        tools.apply_access_decay(conn, factor=0.5)
        res = tools.recompute_dynamic_tiers(conn)
        assert res['success']
        tiers = res['thresholds']
        assert tiers['p90'] >= tiers['p60'] >= tiers['p30']
