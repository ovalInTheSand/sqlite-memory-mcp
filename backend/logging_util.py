"""Lightweight structured logging helper.

Avoids external deps; emits JSON lines to stderr. Can be extended later.
"""
from __future__ import annotations
import os, sys, json, time, threading

_lock = threading.Lock()
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
LEVEL_ORDER = ["DEBUG","INFO","WARN","ERROR"]

def _should(level: str) -> bool:
    try:
        return LEVEL_ORDER.index(level) >= LEVEL_ORDER.index(LOG_LEVEL)
    except ValueError:
        return True

def log(level: str, event: str, **fields):
    if not _should(level.upper()):
        return
    record = {
        "ts": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        "level": level.upper(),
        "event": event,
    }
    record.update(fields)
    line = json.dumps(record, separators=(',',':'))
    with _lock:
        sys.stderr.write(line + "\n")
        sys.stderr.flush()

def debug(event: str, **fields): log("DEBUG", event, **fields)
def info(event: str, **fields): log("INFO", event, **fields)
def warn(event: str, **fields): log("WARN", event, **fields)
def error(event: str, **fields): log("ERROR", event, **fields)
