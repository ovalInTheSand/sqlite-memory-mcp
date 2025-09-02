"""Backend abstraction layer (v0.1)

Defines a minimal interface for memory storage backends so future engines
(e.g., DuckDB, Postgres) can be plugged in with minimal changes.

KISS: Only the operations the current toolkit needs are abstracted.
"""
from __future__ import annotations
from typing import Protocol, Iterable, Any, Optional

class ConnectionLike(Protocol):  # pragma: no cover - structural typing helper
    def execute(self, *args, **kwargs): ...
    def close(self): ...

class Backend(Protocol):
    def connect(self, write: bool) -> ConnectionLike:
        """Return a DB connection. write=False MUST enforce read-only semantics.
        Implementations may raise if write requested but unavailable.
        """
        ...
