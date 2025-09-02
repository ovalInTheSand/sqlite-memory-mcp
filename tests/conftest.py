import os, sqlite3, tempfile, shutil, pytest, pathlib
from pathlib import Path
from templates.mcp_tools import SQLiteMemoryTools

@pytest.fixture()
def temp_db():
    with tempfile.TemporaryDirectory() as d:
        db_path = Path(d)/'test.db'
        # Load schema and migrations via sqlite3 module for error handling
        conn = sqlite3.connect(db_path)
        try:
            schema_sql = Path('sql/schema.sql').read_text(encoding='utf-8')
            conn.executescript(schema_sql)
            for mig in sorted(Path('sql/migrations').glob('*.sql')):
                mig_sql = mig.read_text(encoding='utf-8')
                conn.executescript(mig_sql)
        finally:
            conn.close()
        yield str(db_path)

@pytest.fixture()
def tools(temp_db, monkeypatch):
    monkeypatch.setenv('ALLOW_WRITES','1')
    return SQLiteMemoryTools(temp_db)
