"""Minimal offline test runner (stdlib only) for core smoke checks.

Usage:
  python test_runner.py                 # runs all checks

Skips full pytest suite; intended as a fallback when pip/pytest unavailable.
"""
from __future__ import annotations
import json, os, sqlite3, sys, traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from backend.sqlite_backend import SQLiteBackend  # type: ignore

DB_PATH = Path(os.environ.get("CLAUDE_MEMORY_DB", ROOT / "data" / "memory.db"))


def ensure_db():
    if DB_PATH.exists():
        return
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    # Use deploy_init if available; otherwise create minimal schema version marker
    deploy = ROOT / "scripts" / "deploy_init.py"
    if deploy.exists():
        os.system(f"{sys.executable} {deploy} {DB_PATH}")
    else:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            conn.execute("INSERT INTO settings (key,value) VALUES ('schema_version','2.6')")


def check_health():
    be = SQLiteBackend(str(DB_PATH))
    health = be.health_check()
    assert health["ok"], f"Health not ok: {health}"
    for k in ["journal_mode", "foreign_keys", "cache_size"]:
        assert k in health, f"Missing key {k} in health"
    return health


def main():
    ensure_db()
    results = {}
    failures = 0
    for name, fn in [("health_check", check_health)]:
        try:
            results[name] = fn()
        except Exception:
            failures += 1
            results[name] = {"error": traceback.format_exc()}
    print(json.dumps({"failures": failures, "results": results}, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
