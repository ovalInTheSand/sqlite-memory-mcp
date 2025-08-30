#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

# Load centralized settings
# shellcheck disable=SC1091
source "$root/config/settings.env"

# 1) System packages - smart installation
install_system_deps() {
    local missing_deps=()
    local need_dev_tools=false
    
    # Check SQLite3
    if ! command -v sqlite3 >/dev/null 2>&1; then
        missing_deps+=(sqlite3 sqlite3-doc)
        echo "📦 SQLite3 not found, will install"
    else
        echo "✅ SQLite3 found: $(sqlite3 --version | cut -d' ' -f1)"
        
        # Check for required features
        if ! sqlite3 :memory: "SELECT sqlite_compileoption_used('ENABLE_FTS5');" | grep -q 1; then
            echo "⚠️  SQLite3 missing FTS5 support, may need to upgrade"
            missing_deps+=(sqlite3 sqlite3-doc)
        fi
        
        if ! sqlite3 :memory: "SELECT sqlite_compileoption_used('ENABLE_JSON1');" | grep -q 1; then
            echo "⚠️  SQLite3 missing JSON1 support, may need to upgrade"
            missing_deps+=(sqlite3 sqlite3-doc)
        fi
    fi
    
    # Check development libraries (needed for mcp-server-sqlite compilation)
    if ! pkg-config --exists sqlite3 2>/dev/null; then
        missing_deps+=(libsqlite3-dev)
        need_dev_tools=true
    fi
    
    # Check build tools
    if ! command -v gcc >/dev/null 2>&1; then
        missing_deps+=(build-essential)
        need_dev_tools=true
    fi
    
    # Check pipx
    if ! command -v pipx >/dev/null 2>&1; then
        missing_deps+=(pipx)
    fi
    
    # Install only what's missing
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "📦 Installing missing packages: ${missing_deps[*]}"
        
        # Check if we can use sudo
        if ! sudo -n true 2>/dev/null; then
            echo "❌ Need sudo access to install: ${missing_deps[*]}"
            echo "Please run: sudo apt install ${missing_deps[*]}"
            exit 1
        fi
        
        sudo apt update -y
        sudo apt install -y "${missing_deps[@]}"
    else
        echo "✅ All system dependencies satisfied"
    fi
    
    # Ensure pipx path
    if command -v pipx >/dev/null 2>&1; then
        pipx ensurepath >/dev/null 2>&1 || true
    fi
}

install_system_deps

# 2) Ensure memory home
mkdir -p "$HOME/.claude/memory"

# 3) Bootstrap PRAGMAs (rewrite with env values; idempotent)
cat > "$root/sql/bootstrap.sql" <<SQL
-- =============== CORE PRAGMAS (Enhanced for Performance) ===============
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=${BUSY_TIMEOUT_MS};
PRAGMA cache_size=-${CACHE_SIZE_KIB};
PRAGMA temp_store=MEMORY;
PRAGMA mmap_size=${MMAP_SIZE_BYTES};
PRAGMA synchronous=${SYNCHRONOUS_LEVEL};
PRAGMA journal_mode=${ENABLE_WAL:+WAL};
PRAGMA wal_autocheckpoint=${WAL_AUTOCHECKPOINT:-1000};
PRAGMA user_version=2;
PRAGMA application_id=0x434C4D50; -- 'CLMP'

-- =============== OPTIMIZATION SETTINGS ===============
PRAGMA optimize;
PRAGMA analysis_limit=1000;

-- =============== PERFORMANCE MONITORING SETUP ===============
-- Schema will populate the monitoring tables
SQL

# 4) Apply bootstrap + schema
sqlite3 "$CLAUDE_MEMORY_DB" < "$root/sql/bootstrap.sql"
sqlite3 "$CLAUDE_MEMORY_DB" < "$root/sql/schema.sql"

# 5) Quick checks
sqlite3 "$CLAUDE_MEMORY_DB" <<'SQL'
.headers off
.mode list
SELECT 'fts5', sqlite_compileoption_used('ENABLE_FTS5');
SELECT 'json1', sqlite_compileoption_used('ENABLE_JSON1');
PRAGMA journal_mode;
PRAGMA foreign_keys;
PRAGMA application_id;
SQL

# 6) Install SQLite MCP server (stdio)
pipx install mcp-server-sqlite || true

# 7) Planner hint
sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA optimize;"

echo "✅ SQLite + schema applied at: $CLAUDE_MEMORY_DB"
echo "✅ Installed mcp-server-sqlite (if not already)"
echo "Next step: register MCP (user or project scope)."
