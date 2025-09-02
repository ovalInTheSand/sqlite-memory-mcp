#!/usr/bin/env python3
"""Idempotent deployment initializer.

Creates (or upgrades) the SQLite database by applying base schema then sequential
migrations in sql/migrations. Safe to run multiple times; existing objects remain.

Usage:
  python scripts/deploy_init.py /path/to/db.sqlite
"""
from __future__ import annotations
import sys, sqlite3, pathlib

SCHEMA_FILE = pathlib.Path('sql/schema.sql')
MIGRATIONS_DIR = pathlib.Path('sql/migrations')

def main():
    if len(sys.argv) < 2:
        print('Usage: deploy_init.py <db_path>', file=sys.stderr)
        return 2
    db_path = pathlib.Path(sys.argv[1])
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    try:
        with conn:  # implicit transaction per executescript chunk
            schema_sql = SCHEMA_FILE.read_text(encoding='utf-8')
            conn.executescript(schema_sql)
            if MIGRATIONS_DIR.exists():
                for mig in sorted(MIGRATIONS_DIR.glob('*.sql')):
                    mig_sql = mig.read_text(encoding='utf-8')
                    conn.executescript(mig_sql)
    finally:
        conn.close()
    print(f"initialized: {db_path}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
