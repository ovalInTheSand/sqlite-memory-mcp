import os, sqlite3, tempfile, pathlib
import subprocess, sys, json
import pytest
from backend.sqlite_backend import SQLiteBackend, BackendConfig, MAX_CACHE_KIB, MAX_MMAP_BYTES


def test_missing_file_immutable_mode(tmp_path):
    db_path = tmp_path / 'does_not_exist.db'
    be = SQLiteBackend(str(db_path))
    with pytest.raises(sqlite3.OperationalError) as exc:
        be.connect(write=False)
    assert 'not found' in str(exc.value).lower()


def test_env_clamping(monkeypatch, tmp_path):
    db_path = tmp_path / 'x.db'
    # Create an empty database file (writable) then close
    sqlite3.connect(db_path).close()
    monkeypatch.setenv('CACHE_SIZE_KIB', str(MAX_CACHE_KIB * 10))
    monkeypatch.setenv('MMAP_SIZE_BYTES', str(MAX_MMAP_BYTES * 10))
    monkeypatch.setenv('WAL_AUTOCHECKPOINT', '999999999')
    be = SQLiteBackend(str(db_path))
    conn = be.connect(write=True)
    try:
        # fetch actual pragmas applied (cache_size negative => pages, so just ensure not absurd)
        cache_size = conn.execute('PRAGMA cache_size').fetchone()[0]
        mmap_size = conn.execute('PRAGMA mmap_size').fetchone()[0]
        assert abs(cache_size) <= MAX_CACHE_KIB  # negative value indicates kib pages
        assert mmap_size <= MAX_MMAP_BYTES
    finally:
        conn.close()


def test_health_check(tmp_path):
    db_path = tmp_path / 'h.db'
    sqlite3.connect(db_path).close()
    be = SQLiteBackend(str(db_path))
    hc = be.health_check()
    assert hc['ok'] is True
    assert hc['path'].endswith('h.db')
    assert 'journal_mode' in hc


def test_connection_pool_reuse(monkeypatch, tmp_path):
    db_path = tmp_path / 'p.db'
    sqlite3.connect(db_path).close()
    monkeypatch.setenv('BACKEND_POOL_SIZE', '2')
    be = SQLiteBackend(str(db_path))
    c1 = be.connect(write=True)
    id1 = be.get_connection_id(c1)
    c1.close()  # should return to pool
    c2 = be.connect(write=True)
    id2 = be.get_connection_id(c2)
    assert id1 == id2  # reused
    c2.close()
    be.close_all()


def test_no_pool_wrapper(monkeypatch, tmp_path):
    """Ensure pool_size=0 returns raw sqlite3.Connection (no _inner attr)."""
    db_path = tmp_path / 'nopool.db'
    sqlite3.connect(db_path).close()
    monkeypatch.setenv('BACKEND_POOL_SIZE', '0')
    be = SQLiteBackend(str(db_path))
    c = be.connect(write=True)
    assert not hasattr(c, '_inner')
    c.close()


def test_trusted_schema_off(tmp_path):
    """trusted_schema should be OFF in write connections for safety."""
    db_path = tmp_path / 'trusted.db'
    sqlite3.connect(db_path).close()
    be = SQLiteBackend(str(db_path))
    with be.connect(write=True) as c:
        val = c.execute('PRAGMA trusted_schema').fetchone()[0]
        # Some SQLite builds may return "0" or integer 0; normalize
        assert str(val) in {"0", "off", "OFF"}


def test_health_check_keys(tmp_path):
    db_path = tmp_path / 'health_keys.db'
    sqlite3.connect(db_path).close()
    be = SQLiteBackend(str(db_path))
    hc = be.health_check()
    for k in ['ok','foreign_keys','journal_mode','cache_size','mmap_size','wal_autocheckpoint']:
        assert k in hc


def test_immutable_write_denial(tmp_path):
    """Test that immutable mode truly blocks write operations"""
    db_path = tmp_path / 'readonly.db'
    # Create database with a simple table
    conn = sqlite3.connect(db_path)
    conn.execute("CREATE TABLE test_table (id INTEGER PRIMARY KEY, data TEXT)")
    conn.execute("INSERT INTO test_table (data) VALUES ('initial')")
    conn.commit()
    conn.close()
    
    # Set to read-only permissions
    import os
    os.chmod(db_path, 0o444)
    
    be = SQLiteBackend(str(db_path))
    conn = be.connect(write=False)  # immutable mode
    
    # Should be able to read
    result = conn.execute("SELECT COUNT(*) FROM test_table").fetchone()
    assert result[0] == 1
    
    # Should fail to write
    with pytest.raises(sqlite3.OperationalError) as exc:
        conn.execute("INSERT INTO test_table (data) VALUES ('blocked')")
    assert 'readonly' in str(exc.value).lower() or 'disk' in str(exc.value).lower()
    
    conn.close()


def test_invalid_env_values_warning(monkeypatch, tmp_path, capsys):
    """Test that invalid env values produce warnings and use defaults"""
    db_path = tmp_path / 'x.db'
    sqlite3.connect(db_path).close()
    
    # Set invalid non-integer values
    monkeypatch.setenv('CACHE_SIZE_KIB', 'not-a-number')
    monkeypatch.setenv('MMAP_SIZE_BYTES', 'invalid')
    monkeypatch.setenv('WAL_AUTOCHECKPOINT', 'bad-value')
    
    be = SQLiteBackend(str(db_path))
    
    # Check that warnings were logged to stderr for invalid values
    captured = capsys.readouterr()
    assert 'invalid_env_int' in captured.err
    assert 'CACHE_SIZE_KIB' in captured.err
    assert 'not-a-number' in captured.err
    
    # Verify defaults were used (we can check this via health_check)
    hc = be.health_check()
    assert hc['ok'] is True


def test_verify_on_connect_integrity(monkeypatch, tmp_path):
    """Test VERIFY_ON_CONNECT integrity check functionality"""
    db_path = tmp_path / 'verify.db'
    conn = sqlite3.connect(db_path)
    conn.execute("CREATE TABLE test (id INTEGER)")
    conn.execute("INSERT INTO test VALUES (1)")
    conn.commit()  # Make sure data is written
    conn.close()
    
    monkeypatch.setenv('VERIFY_ON_CONNECT', '1')
    be = SQLiteBackend(str(db_path))
    
    # Verify integrity check runs (should pass for healthy DB)
    # The test is mainly that connection succeeds without errors
    conn = be.connect(write=True)
    
    # Verify the database content is accessible
    result = conn.execute("SELECT COUNT(*) FROM test").fetchone()
    assert result[0] == 1
    
    conn.close()


def test_high_level_write_denial_readonly_mode(monkeypatch):
    """Test that high-level API denies writes when ALLOW_WRITES=0"""
    from templates.mcp_tools import SQLiteMemoryTools
    
    # Create a temporary database
    import tempfile
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as tmp:
        db_path = tmp.name
    
    try:
        # Initialize database with basic schema
        os.system(f"sqlite3 {db_path} 'CREATE TABLE agent_quota (agent_id INTEGER, table_count INTEGER)'")
        
        # Set read-only mode
        monkeypatch.setenv('ALLOW_WRITES', '0')
        tools = SQLiteMemoryTools(db_path)
        
        # Should fail to create agent table (requires write)
        result = tools.create_agent_table(1, "test_table", "CREATE TABLE test_table (id INTEGER)", "test")
        assert result.get('error') is not None
        assert 'read-only' in str(result.get('error', '')).lower() or 'write' in str(result.get('error', '')).lower()
        
    finally:
        os.unlink(db_path)


def test_allow_writes_hot_reload(monkeypatch, temp_db):
    """ALLOW_WRITES hot reload: toolkit re-reads environment dynamically."""
    import sqlite3
    from templates.mcp_tools import SQLiteMemoryTools
    
    # Insert required agent for foreign key constraint
    with sqlite3.connect(temp_db) as conn:
        conn.execute("INSERT INTO agents(name,kind) VALUES('test_agent','claude-code')")
    
    # Start in read-only
    monkeypatch.setenv('ALLOW_WRITES', '0')
    tools = SQLiteMemoryTools(temp_db)
    # Attempt to create agent table should fail
    r1 = tools.create_agent_table(1, 'hot_reload_table', 'CREATE TABLE hot_reload_table(id INTEGER)', 'hot reload test')
    assert not r1['success']
    # Enable writes and retry with new table name
    monkeypatch.setenv('ALLOW_WRITES', '1')
    r2 = tools.create_agent_table(1, 'hot_reload_table2', 'CREATE TABLE hot_reload_table2(id INTEGER)', 'hot reload test')
    assert r2['success']


def test_smoke_script_toggle_and_health(monkeypatch, temp_db):
    """Run smoke_test with toggle + health_check validation enabled."""
    # Prepare env: start read-only so toggle path triggers
    monkeypatch.setenv('ALLOW_WRITES', '0')
    monkeypatch.setenv('SMOKE_TOGGLE_WRITES', '1')
    monkeypatch.setenv('SMOKE_HEALTH_CHECK', '1')
    monkeypatch.setenv('CLAUDE_MEMORY_DB', temp_db)
    # Execute smoke test script as subprocess to emulate real invocation
    result = subprocess.run([sys.executable, 'scripts/smoke_test.py'], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Smoke test failed: {result.stderr} {result.stdout}"
    # Parse JSON
    data = json.loads(result.stdout.strip().splitlines()[-1])
    assert data.get('success') is True
