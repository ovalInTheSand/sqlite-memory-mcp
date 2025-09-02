#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if [ ! -d "$VENV_DIR" ]; then
  echo "[venv] Creating virtual environment in .venv" >&2
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "[venv] Upgrading pip/setuptools/wheel" >&2
pip install --upgrade pip setuptools wheel

echo "[venv] Installing runtime requirements" >&2
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi

echo "[venv] Installing dev requirements" >&2
if [ -f requirements-dev.txt ]; then
  pip install -r requirements-dev.txt
fi

echo "[venv] Environment ready. Activate with: source .venv/bin/activate" >&2
