#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck disable=SC1091
source "$root/config/settings.env"

claude mcp add "${MCP_SERVER_NAME:-sqlite_memory}" --scope user -- \
  mcp-server-sqlite --db-path "${CLAUDE_MEMORY_DB}"

echo "✅ Added user-scoped MCP server '${MCP_SERVER_NAME:-sqlite_memory}'."
echo "Check: claude mcp list"
