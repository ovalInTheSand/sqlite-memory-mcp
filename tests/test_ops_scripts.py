import os, sys, json, sqlite3, pathlib, subprocess
import pytest

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]

@pytest.fixture()
def tmp_db(tmp_path):
    db = tmp_path / 'ops.db'
    # minimal schema: create needed settings table for health_check to work gracefully
    schema = (PROJECT_ROOT / 'sql' / 'schema.sql').read_text(encoding='utf-8')
    conn = sqlite3.connect(db)
    try:
        conn.executescript(schema)
    finally:
        conn.close()
    return db


def run(cmd, **kw):
    proc = subprocess.run(cmd, capture_output=True, text=True, **kw)
    assert proc.returncode == 0, f"Command failed: {cmd}\n{proc.stdout}\n{proc.stderr}"
    return proc


def test_deploy_init_idempotent(tmp_path):
    db = tmp_path / 'deploy.db'
    script = PROJECT_ROOT / 'scripts' / 'deploy_init.py'
    run([sys.executable, str(script), str(db)], cwd=PROJECT_ROOT)
    # second run should also succeed
    run([sys.executable, str(script), str(db)], cwd=PROJECT_ROOT)
    assert db.exists()


def test_backup_safe(tmp_db, tmp_path, monkeypatch):
    # Insert sample row to ensure non-empty backup
    conn = sqlite3.connect(tmp_db)
    with conn:
        conn.execute("INSERT INTO agents(name,kind) VALUES('a','claude-code')")
    conn.close()
    backup = tmp_path / 'backup.db'
    script = PROJECT_ROOT / 'scripts' / 'backup_safe.py'
    monkeypatch.setenv('ALLOW_WRITES','1')
    run([sys.executable, str(script), str(tmp_db), str(backup)], cwd=PROJECT_ROOT)
    assert backup.exists() and backup.stat().st_size > 0


def test_config_dump(tmp_db):
    # Use module CLI invocation
    proc = run([sys.executable, '-m', 'backend.sqlite_backend', str(tmp_db)], cwd=PROJECT_ROOT)
    data = json.loads(proc.stdout)
    assert 'config' in data and 'health_check' in data
    assert data['health_check'].get('ok') is True


def test_secret_scan_no_obvious_tokens():
    # Simple heuristic: look for patterns like API_KEY= or bearer tokens (not exhaustive)
    suspicious = []
    for path in PROJECT_ROOT.rglob('*'):
        if path.is_dir() or path.suffix in {'.pyc','.db','.sqlite'}:
            continue
        if 'test_' in path.name:  # Skip test files to avoid false positives
            continue
        try:
            text = path.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        if 'API_KEY=' in text or 'Bearer ' in text:
            suspicious.append(str(path))
    assert not suspicious, f"Potential secrets detected: {suspicious}"
