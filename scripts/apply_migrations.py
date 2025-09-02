#!/usr/bin/env python3
"""Lightweight migration runner.

Applies SQL files in sql/migrations sorted lexicographically if their version
string (prefix before first underscore) not yet present in schema_migrations.

Usage: python scripts/apply_migrations.py <db_path>
"""
import sys, sqlite3, pathlib, re

VERSION_RE = re.compile(r"^(\d+_?[^_]*)")

def main():
    if len(sys.argv) < 2:
        print("Usage: apply_migrations.py <db_path>")
        return 1
    db = sys.argv[1]
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')), description TEXT)")
    applied = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
    mig_dir = pathlib.Path('sql/migrations')
    if not mig_dir.exists():
        print("No migrations directory")
        return 0
    executed = 0
    for path in sorted(mig_dir.glob('*.sql')):
        version = path.stem
        if version in applied:
            continue
        sql = path.read_text(encoding='utf-8')
        try:
            conn.executescript(sql)
            conn.execute("INSERT OR IGNORE INTO schema_migrations(version, description) VALUES(?, ?)", (version, None))
            conn.commit()
            executed += 1
            print(f"Applied {version}")
        except sqlite3.Error as e:
            conn.rollback()
            print(f"Failed {version}: {e}")
            return 2
    print(f"Migrations applied: {executed}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
