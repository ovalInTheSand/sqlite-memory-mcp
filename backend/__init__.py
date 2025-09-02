"""Backend package initialization.

Single source of truth for schema + package versions so that code, tests, and
scripts can import without duplicating literals.
"""

SCHEMA_VERSION = "2.6"
PACKAGE_VERSION = "0.3.0"  # Keep in sync with pyproject version.

__all__ = ["SCHEMA_VERSION", "PACKAGE_VERSION"]

