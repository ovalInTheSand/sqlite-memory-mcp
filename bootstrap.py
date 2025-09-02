#!/usr/bin/env python3
"""Cross-platform project bootstrap utility.

One entry point that works on Windows, WSL, Linux, macOS.

Features:
  - Creates (or reuses) a `.venv` virtual environment
  - Installs the package in editable mode (`pip install -e .`)
  - Optional dev/test dependencies (`--dev`)
  - Optional database initialization (`--init-db`) to `./data/memory.db`
  - Optional test run (`--run-tests`) if pytest is installed/available
  - Prints next-step activation guidance for your shell (PowerShell / bash)

Usage examples:
  python bootstrap.py --init-db            # minimal install + create DB
  python bootstrap.py --init-db --dev      # also install pytest, etc.
  python bootstrap.py --init-db --dev --run-tests

Idempotent: safe to re-run; will skip work already done.
"""
from __future__ import annotations
import argparse, os, sys, subprocess, shutil, textwrap, platform
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
VENV_DIR = PROJECT_ROOT / ".venv"
DATA_DIR = PROJECT_ROOT / "data"
DEFAULT_DB = DATA_DIR / "memory.db"


def run(cmd: list[str], **kw):
    """Run a command, raising on non-zero exit."""
    print("[bootstrap] $", " ".join(cmd))
    subprocess.check_call(cmd, **kw)


def ensure_venv(python: str) -> Path:
    if not VENV_DIR.exists():
        print("[bootstrap] Creating virtual environment .venv")
        run([python, "-m", "venv", str(VENV_DIR)])
    # Choose interpreter path (Windows vs POSIX)
    if platform.system().lower().startswith("win"):
        return VENV_DIR / "Scripts" / ("python.exe" if (VENV_DIR / "Scripts" / "python.exe").exists() else "python")
    return VENV_DIR / "bin" / "python"


def pip_install(venv_py: Path, packages: list[str]):
    if not packages:
        return
    run([str(venv_py), "-m", "pip", "install", "-q", "--upgrade", "pip", "setuptools", "wheel"])  # upgrade core
    run([str(venv_py), "-m", "pip", "install", "-e", "."])
    if any(p.endswith("[dev]") or p == ".[dev]" for p in packages):
        run([str(venv_py), "-m", "pip", "install", "-e", ".[dev]"])


def init_db(venv_py: Path, db_path: Path):
    if db_path.exists():
        print(f"[bootstrap] Database already exists: {db_path}")
        return
    db_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"[bootstrap] Initializing database: {db_path}")
    run([str(venv_py), "scripts/deploy_init.py", str(db_path)])


def run_tests(venv_py: Path):
    try:
        run([str(venv_py), "-m", "pytest", "-q"])  # will error if pytest missing
    except FileNotFoundError:
        print("[bootstrap] pytest not installed; skipping tests.")
    except subprocess.CalledProcessError as e:
        print(f"[bootstrap] Test run failed (exit {e.returncode}).")
        raise


def activation_hint():
    ps_hint = ".venv\\Scripts\\Activate.ps1"
    bash_hint = "source .venv/bin/activate"
    return textwrap.dedent(f"""
        Next steps:
          PowerShell: {ps_hint}
          bash/zsh : {bash_hint}

        mem CLI usage after activation:
          mem health
          mem optimize

        Set database path (optional override):
          export CLAUDE_MEMORY_DB=./data/memory.db  # or setx on Windows
    """)


def parse_args(argv: list[str]):
    ap = argparse.ArgumentParser(description="Cross-platform bootstrap")
    ap.add_argument("--dev", action="store_true", help="Install dev/test dependencies")
    ap.add_argument("--init-db", action="store_true", help="Create & migrate local database (data/memory.db)")
    ap.add_argument("--db-path", type=Path, default=DEFAULT_DB, help="Custom DB path (with --init-db)")
    ap.add_argument("--run-tests", action="store_true", help="Run pytest after install (requires --dev or existing pytest)")
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    python = sys.executable
    venv_py = ensure_venv(python)
    # Install dependencies
    pip_install(venv_py, [".[dev]"] if args.dev else ["."])
    # Initialize DB
    if args.init_db:
        init_db(venv_py, args.db_path)
    # Run tests optionally
    if args.run_tests:
        run_tests(venv_py)
    print(activation_hint())
    print("[bootstrap] Done.")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
