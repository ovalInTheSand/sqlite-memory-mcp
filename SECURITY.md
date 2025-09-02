# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.3.x   | Yes       |
| <0.3.0  | Best-effort (upgrade recommended) |

Schema version currently: 2.6 (runtime constant `backend.SCHEMA_VERSION`).

## Reporting a Vulnerability

Please open a private security advisory or email the maintainer (see project author in `pyproject.toml`). Provide:
- A clear description of the issue and potential impact
- Steps to reproduce (proof-of-concept SQL / code snippet if applicable)
- Expected vs actual behavior
- Suggested mitigation (optional)

You will receive an acknowledgement within 3 business days. Critical issues will be prioritized.

## Hardening Features
- Immutable read-only mode (SQLite `immutable=1`, `query_only=ON`)
- Environment configuration clamping (prevents resource exhaustion)
- Integrity verification option (`VERIFY_ON_CONNECT`)
- Structured JSON logging (no PII/output minimization by default)

## Key Environment Controls
| Variable | Purpose | Safe Range |
|----------|---------|------------|
| CACHE_SIZE_KIB | Page cache size (negative = KiB) | 16 - 524288 |
| MMAP_SIZE_BYTES | Memory map size | 1MB - 2GB |
| WAL_AUTOCHECKPOINT | WAL checkpoint target pages | 1 - 100000 |
| BACKEND_POOL_SIZE | Connection pool size (per mode) | 0 - small (<32) |
| VERIFY_ON_CONNECT | Integrity check when opening write connection | 0 or 1 |

## Recommendations
- Run on a filesystem with proper permissions (restrict DB path read/write).
- Backup using `VACUUM INTO` or hot `.backup` including WAL/SHM when writes active.
- Monitor logs for `backend_config_clamped` and `pragma_failed` events.

## Disclosure Timeline
Security advisories and patches will be documented in `VERSION.md` under future releases.
