#!/usr/bin/env python3
"""Smoke test for core invariants.

Checks:
    * Schema version matches expected
  * Required triggers exist (memory_access_tracker, memory_auto_archive)
  * Removed touch triggers absent
  * Retention setting present
  * Read-only mode respected when ALLOW_WRITES=0 (attempt write should fail)
    * (Optional) Toggle ALLOW_WRITES from 0->1 validates hot permission reload (set SMOKE_TOGGLE_WRITES=1)
    * (Optional) health_check output is JSON parseable and contains required keys (set SMOKE_HEALTH_CHECK=1)
"""
import os, sqlite3, sys, json
from contextlib import closing
try:
    from templates.mcp_tools import SQLiteMemoryTools
except Exception:
    SQLiteMemoryTools = None  # Toolkit optional for minimal smoke
from backend import SCHEMA_VERSION as EXPECTED_VERSION
from pathlib import Path

DB_PATH = os.environ.get('CLAUDE_MEMORY_DB', str(Path.home()/'.claude'/'memory'/'claude_memory.db'))

failures = []

def check(cond, msg):
    if not cond:
        failures.append(msg)

if not Path(DB_PATH).exists():
    print(json.dumps({'success': False, 'error': f'DB missing: {DB_PATH}'}))
    sys.exit(1)

conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

# Version
cur.execute("SELECT value FROM settings WHERE key='schema_version'")
row = cur.fetchone()
check(row and row[0] == EXPECTED_VERSION, f"schema_version mismatch: got {row and row[0]}")

# Triggers
cur.execute("SELECT name FROM sqlite_master WHERE type='trigger'")
trigs = {r[0] for r in cur.fetchall()}
check('memory_access_tracker' in trigs, 'missing memory_access_tracker')
check('memory_auto_archive' in trigs, 'missing memory_auto_archive')
# Ensure removed triggers absent
for t in ['projects_ut','agents_ut','memory_ut','docs_ut']:
    check(t not in trigs, f"deprecated trigger still present: {t}")

# Retention + dynamic tier settings
required_settings = [
    'performance_monitoring_retention_days',
    'tier_hot_threshold','tier_warm_threshold','tier_cold_threshold'
]
cur.execute("SELECT key FROM settings WHERE key IN (?,?,?,?)", required_settings)
found = {r[0] for r in cur.fetchall()}
for s in required_settings:
    check(s in found, f'missing setting: {s}')

allow_writes_env = os.environ.get('ALLOW_WRITES','0')

# Immutable read test (if ALLOW_WRITES=0) - test through toolkit, not direct SQLite
if allow_writes_env != '1' and SQLiteMemoryTools:
    tools = SQLiteMemoryTools(DB_PATH)
    # Should fail when trying to create through toolkit
    result = tools.create_agent_table(999, '__write_test', 'CREATE TABLE __write_test(id INTEGER)', 'test')
    check(not result.get('success'), 'toolkit write unexpectedly succeeded in read-only mode')

# Optional toggle test
if os.environ.get('SMOKE_TOGGLE_WRITES','0') == '1' and SQLiteMemoryTools:
    # Ensure starting state is read-only
    if allow_writes_env != '1':
        # Now enable writes and test via toolkit (hot reload)
        os.environ['ALLOW_WRITES'] = '1'
        tools = SQLiteMemoryTools(DB_PATH)
        # Create a trivial table through direct connection to avoid requiring migrations
        with tools.get_connection() as c:
            try:
                c.execute("CREATE TABLE IF NOT EXISTS __toggle_test(id INTEGER PRIMARY KEY)")
                c.execute("INSERT INTO __toggle_test(id) VALUES (1)")
            except sqlite3.Error as e:
                check(False, f'write failed after enabling ALLOW_WRITES: {e}')

# Optional health_check validation
if os.environ.get('SMOKE_HEALTH_CHECK','0') == '1' and SQLiteMemoryTools:
    tools = SQLiteMemoryTools(DB_PATH)
    hc = tools.backend.health_check()
    required_hc = {'ok','foreign_keys','journal_mode','cache_size','mmap_size'}
    missing = required_hc - hc.keys() if isinstance(hc, dict) else required_hc
    if missing:
        check(False, f"health_check missing keys: {sorted(missing)}")

conn.close()

if failures:
    print(json.dumps({'success': False, 'failures': failures}))
    sys.exit(2)
print(json.dumps({'success': True}))
