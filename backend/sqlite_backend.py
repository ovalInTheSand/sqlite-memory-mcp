"""SQLite backend implementation supporting immutable read-only mode.

Enhancements (v2.5+):
    - Immutable (query_only + immutable=1) mode for defense in depth when ALLOW_WRITES=0
    - Environment driven tuning with clamping + sanity logging
    - Optional connection pooling (very small, LRU-less simple stack) via BACKEND_POOL_SIZE
    - Health check helper + optional integrity_check (VERIFY_ON_CONNECT=1)
    - Clearer error messages for missing files in immutable mode & directory path misuse
"""
from __future__ import annotations
import sqlite3, os
from dataclasses import dataclass
from .logging_util import warn, debug
from typing import Any, Optional, Dict, List

MAX_CACHE_KIB = 512 * 1024        # 512 MiB upper clamp
MIN_CACHE_KIB = 16                # SQLite minimum practical
DEFAULT_CACHE_KIB = 64 * 1024     # 64 MiB
MAX_MMAP_BYTES = 2 * 1024 * 1024 * 1024  # 2 GiB
MIN_MMAP_BYTES = 1 * 1024 * 1024        # 1 MiB
DEFAULT_MMAP_BYTES = 256 * 1024 * 1024  # 256 MiB
MAX_WAL_AUTOCHECKPOINT = 100_000
DEFAULT_WAL_AUTOCHECKPOINT = 1000

@dataclass
class BackendConfig:
    cache_kib: int = DEFAULT_CACHE_KIB
    mmap_bytes: int = DEFAULT_MMAP_BYTES
    wal_autocheckpoint: int = DEFAULT_WAL_AUTOCHECKPOINT
    pool_size: int = 0
    verify_on_connect: bool = False

    @classmethod
    def from_env(cls) -> "BackendConfig":
        def _int(name: str, default: int) -> int:
            raw = os.environ.get(name)
            if raw is None:
                return default
            try:
                return int(raw)
            except ValueError:
                warn("invalid_env_int", key=name, value=raw, default=default)
                return default
        cache_kib = _int("CACHE_SIZE_KIB", DEFAULT_CACHE_KIB)
        mmap_bytes = _int("MMAP_SIZE_BYTES", DEFAULT_MMAP_BYTES)
        wal_ac = _int("WAL_AUTOCHECKPOINT", DEFAULT_WAL_AUTOCHECKPOINT)
        pool_size = max(0, _int("BACKEND_POOL_SIZE", 0))
        verify = os.environ.get("VERIFY_ON_CONNECT", "0") == "1"
        # Clamp
        adjusted = {}
        if cache_kib < MIN_CACHE_KIB or cache_kib > MAX_CACHE_KIB:
            adjusted["cache_kib"] = cache_kib
            cache_kib = min(MAX_CACHE_KIB, max(MIN_CACHE_KIB, cache_kib))
        if mmap_bytes < MIN_MMAP_BYTES or mmap_bytes > MAX_MMAP_BYTES:
            adjusted["mmap_bytes"] = mmap_bytes
            mmap_bytes = min(MAX_MMAP_BYTES, max(MIN_MMAP_BYTES, mmap_bytes))
        if wal_ac < 1 or wal_ac > MAX_WAL_AUTOCHECKPOINT:
            adjusted["wal_autocheckpoint"] = wal_ac
            wal_ac = min(MAX_WAL_AUTOCHECKPOINT, max(1, wal_ac))
        if adjusted:
            final_values = {"cache_kib": cache_kib, "mmap_bytes": mmap_bytes, "wal_autocheckpoint": wal_ac}
            warn("backend_config_clamped", original=adjusted, clamped=final_values)
        return cls(cache_kib=cache_kib, mmap_bytes=mmap_bytes, wal_autocheckpoint=wal_ac, pool_size=pool_size, verify_on_connect=verify)

class _PooledConnection:
    """Light wrapper so .close() returns connection to pool instead of really closing."""
    def __init__(self, inner: sqlite3.Connection, pool: List[sqlite3.Connection], max_pool: int):
        self._inner = inner
        self._pool = pool
        self._max_pool = max_pool
    def __getattr__(self, item):
        return getattr(self._inner, item)
    def close(self):  # type: ignore[override]
        if self._inner is None:
            return
        if len(self._pool) < self._max_pool:
            self._pool.append(self._inner)
        else:
            try:
                self._inner.close()
            except Exception:
                pass
        self._inner = None  # type: ignore

class SQLiteBackend:
    """SQLite backend.

    Responsibilities:
      - Provide connections in read-only immutable or writable mode
      - Apply tuned pragmas with safe clamping
      - Optional small connection pool (opt-in)
      - Health check utility
    """
    def __init__(self, path: str, config: Optional[BackendConfig] = None):
        if os.path.isdir(path):  # directory misuse
            raise ValueError(f"Path points to a directory, expected file: {path}")
        self.path = path
        self.config = config or BackendConfig.from_env()
        # pools keyed by write flag
        self._pools: Dict[bool, List[sqlite3.Connection]] = {True: [], False: []}
        self._pool_hits: int = 0
        self._pool_misses: int = 0

    # --- Public API -----------------------------------------------------------------
    def connect(self, write: bool) -> sqlite3.Connection:
        """Return a configured sqlite3.Connection.

        write=False enforces immutable read-only using URI (mode=ro&immutable=1) and query_only.
        Raises sqlite3.OperationalError with clearer message if file missing in immutable mode.
        May return pooled connections if BACKEND_POOL_SIZE > 0.
        """
        if not write and not os.path.exists(self.path):
            # Friendly pre-check before SQLite cryptic error
            raise sqlite3.OperationalError(f"Database not found and immutable read requested: {self.path}")

        # Reuse pooled connection if available
        if self.config.pool_size > 0 and self._pools[write]:
            conn = self._pools[write].pop()
            self._pool_hits += 1
            return _PooledConnection(conn, self._pools[write], self.config.pool_size)  # type: ignore
        if self.config.pool_size > 0:
            self._pool_misses += 1

        try:
            if write:
                conn = sqlite3.connect(self.path)
            else:
                uri = f"file:{self.path}?mode=ro&immutable=1"
                conn = sqlite3.connect(uri, uri=True)
        except sqlite3.OperationalError as e:
            if not write:
                # Augment message for operators
                raise sqlite3.OperationalError(str(e) + " (database not found and immutable read requested)") from e
            raise

        conn.row_factory = sqlite3.Row
        self._apply_pragmas(conn, write)
        if self.config.verify_on_connect and write:
            try:
                res = conn.execute("PRAGMA integrity_check").fetchone()[0]
                if res != "ok":
                    warn("integrity_check_failed", path=self.path, result=res)
            except Exception as e:  # pragma: no cover - unexpected
                warn("integrity_check_error", error=str(e))
        return conn if self.config.pool_size == 0 else _PooledConnection(conn, self._pools[write], self.config.pool_size)  # type: ignore

    def health_check(self) -> Dict[str, Any]:
        """Return current core pragma values and basic status."""
        try:
            conn = self.connect(write=False)
        except Exception as e:
            return {"ok": False, "error": str(e)}
        try:
            rows = {
                "foreign_keys": conn.execute("PRAGMA foreign_keys").fetchone()[0],
                "journal_mode": conn.execute("PRAGMA journal_mode").fetchone()[0],
                "synchronous": conn.execute("PRAGMA synchronous").fetchone()[0],
                "cache_size": conn.execute("PRAGMA cache_size").fetchone()[0],
                "mmap_size": conn.execute("PRAGMA mmap_size").fetchone()[0],
                "wal_autocheckpoint": conn.execute("PRAGMA wal_autocheckpoint").fetchone()[0],
            }
            if self.config.pool_size > 0:
                rows.update({
                    "pool_size_configured": self.config.pool_size,
                    "pool_available_read": len(self._pools[False]),
                    "pool_available_write": len(self._pools[True]),
                    "pool_hits": self._pool_hits,
                    "pool_misses": self._pool_misses,
                })
            return {"ok": True, "path": self.path, **rows}
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def get_connection_id(self, conn) -> int:
        """Get a unique ID for a connection (for testing connection reuse)"""
        if hasattr(conn, '_inner'):  # _PooledConnection
            return id(conn._inner)
        return id(conn)

    # --- Internal -------------------------------------------------------------------
    def _apply_pragmas(self, conn: sqlite3.Connection, write: bool) -> None:
        mode = "write" if write else "immutable_ro"
        try:
            conn.execute("PRAGMA foreign_keys=ON")
            conn.execute("PRAGMA busy_timeout=30000")
            if write:
                try:
                    jm = conn.execute("PRAGMA journal_mode=WAL").fetchone()[0]
                    if jm.lower() != "wal":
                        warn("journal_mode_unexpected", got=jm, path=self.path)
                except Exception as e:
                    warn("pragma_failed", pragma="journal_mode=WAL", mode=mode, path=self.path, error=str(e))
                # Tunables
                pragmas = [
                    (f"cache_size=-{self.config.cache_kib}", "cache_size"),  # negative => KiB
                    (f"mmap_size={self.config.mmap_bytes}", "mmap_size"),
                    (f"wal_autocheckpoint={self.config.wal_autocheckpoint}", "wal_autocheckpoint"),
                    ("synchronous=NORMAL", "synchronous"),
                    ("trusted_schema=OFF", "trusted_schema"),
                ]
                for p, tag in pragmas:
                    try:
                        conn.execute(f"PRAGMA {p}")
                    except Exception as e:
                        warn("pragma_failed", pragma=p, tag=tag, mode=mode, path=self.path, error=str(e))
            else:
                try:
                    conn.execute("PRAGMA query_only=ON")
                except Exception as e:
                    debug("pragma_query_only_failed", mode=mode, path=self.path, error=str(e))
        except Exception as e:
            warn("connection_pragmas_failed", mode=mode, path=self.path, error=str(e))

    def close_all(self):
        """Close all pooled connections (use in test teardown / shutdown)."""
        for pool in self._pools.values():
            while pool:
                c = pool.pop()
                try:
                    c.close()
                except Exception:
                    pass


def cli_dump_config():  # pragma: no cover - thin CLI wrapper
    """CLI helper: print resolved BackendConfig + health_check JSON."""
    import argparse, json
    ap = argparse.ArgumentParser(description='Dump backend config and health info')
    ap.add_argument('db', help='Path to SQLite database')
    ap.add_argument('--write', action='store_true', help='Open in write mode to show write pragmas')
    args = ap.parse_args()
    be = SQLiteBackend(args.db)
    cfg = be.config.__dict__.copy()
    hc = be.health_check()
    out = {'config': cfg, 'health_check': hc}
    print(json.dumps(out, indent=2))

if __name__ == '__main__':  # pragma: no cover
    cli_dump_config()

