#!/usr/bin/env python3
"""Create a consistent backup of the SQLite database.

If writes permitted, performs `PRAGMA wal_checkpoint(FULL)` then uses VACUUM INTO
for a compact copy. If read-only mode (ALLOW_WRITES!=1), falls back to .backup
semantic by attaching and copying.

Usage:
  python scripts/backup_safe.py /path/to/db.sqlite /path/to/backup.sqlite
"""
from __future__ import annotations
import os, sys, sqlite3, pathlib, time

def main():
    if len(sys.argv) < 3:
        print('Usage: backup_safe.py <db_path> <backup_path>', file=sys.stderr)
        return 2
    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2])
    if not src.exists():
        print(f"source missing: {src}", file=sys.stderr)
        return 1
    allow = os.environ.get('ALLOW_WRITES','0') == '1'
    start = time.time()
    conn = sqlite3.connect(src)
    try:
        if allow:
            try:
                conn.execute('PRAGMA wal_checkpoint(FULL)')
            except sqlite3.Error:
                pass
            # VACUUM INTO creates a consistent compact copy
            conn.execute(f"VACUUM INTO '{dst}'")
        else:
            # Fallback attach copy (read-only environment)
            bconn = sqlite3.connect(dst)
            try:
                with bconn:
                    conn.backup(bconn)  # uses API-level hot backup
            finally:
                bconn.close()
    finally:
        conn.close()
    dur_ms = int((time.time()-start)*1000)
    print(f"backup_created path={dst} ms={dur_ms}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
