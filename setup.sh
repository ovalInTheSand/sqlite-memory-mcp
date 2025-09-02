#!/usr/bin/env bash
set -euo pipefail

# Enhanced SQLite Memory MCP - Interactive Setup
# Provides guided installation with validation and error recovery

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Utility functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🚀 $1${NC}"; }

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local description=$3
    local width=40
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    printf "\r${CYAN}[%s%s] %d%% - %s${NC}" \
        "$(printf "%*s" $completed | tr ' ' '=')" \
        "$(printf "%*s" $remaining)" \
        $percentage \
        "$description"
    
    if [ $current -eq $total ]; then
        echo
    fi
}

# Header
clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Enhanced SQLite Memory MCP Setup                ║"
echo "║         Interactive Installation & Configuration             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo

# Get script directory
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Configuration variables
CLAUDE_MEMORY_DB=""
MCP_SERVER_NAME="sqlite_memory"
SETUP_SCOPE=""
ENABLE_WRITES=""
PERFORMANCE_LEVEL=""

# Step 1: Welcome and pre-flight checks
log_step "Step 1/6: Pre-flight Checks"
show_progress 1 6 "Checking system requirements..."

# Check required commands and SQLite features
check_dependencies() {
    local missing_deps=()
    local warnings=()
    
    # Check SQLite3
    if ! command -v sqlite3 >/dev/null 2>&1; then
        missing_deps+=("sqlite3")
    else
        SQLITE_VERSION=$(sqlite3 --version | cut -d' ' -f1)
        echo "  SQLite version: $SQLITE_VERSION"
        
        # Check for critical features our enhanced schema needs
        if ! sqlite3 :memory: "SELECT sqlite_compileoption_used('ENABLE_FTS5');" | grep -q 1; then
            warnings+=("SQLite lacks FTS5 support - search features will be limited")
        fi
        
        if ! sqlite3 :memory: "SELECT sqlite_compileoption_used('ENABLE_JSON1');" | grep -q 1; then
            warnings+=("SQLite lacks JSON1 support - some features may not work")
        fi
        
        # Check if it's too old
        SQLITE_MAJOR=$(echo "$SQLITE_VERSION" | cut -d'.' -f1)
        SQLITE_MINOR=$(echo "$SQLITE_VERSION" | cut -d'.' -f2)
        if [ "$SQLITE_MAJOR" -lt 3 ] || ([ "$SQLITE_MAJOR" -eq 3 ] && [ "$SQLITE_MINOR" -lt 35 ]); then
            warnings+=("SQLite version $SQLITE_VERSION is quite old - consider upgrading")
        fi
    fi
    
    # Check Python3
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    else
        PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
        echo "  Python version: $PYTHON_VERSION"
    fi
    
    # Check Claude CLI
    if ! command -v claude >/dev/null 2>&1; then
        missing_deps+=("claude")
        echo "  ⚠️  Claude CLI not found - MCP features will need manual setup"
    else
        echo "  ✅ Claude CLI found"
    fi
    
    # Report findings
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warning "Missing dependencies: ${missing_deps[*]}"
        echo "This installer will attempt to install missing dependencies."
    fi
    
    if [ ${#warnings[@]} -gt 0 ]; then
        echo
        for warning in "${warnings[@]}"; do
            log_warning "$warning"
        done
        echo "Installation will continue, but you may want to upgrade later."
    fi
    
    # Critical check - can we proceed?
    if [[ " ${missing_deps[*]} " =~ " python3 " ]] && [[ " ${missing_deps[*]} " =~ " sqlite3 " ]]; then
        log_error "Both Python3 and SQLite3 are missing. Please install them first:"
        echo "  sudo apt install python3 sqlite3"
        return 1
    fi
    
    return 0
}

check_dependencies || exit 1

# Check disk space (need at least 100MB)
AVAILABLE_SPACE=$(df "$HOME" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_SPACE" -lt 102400 ]; then  # 100MB in KB
    log_error "Insufficient disk space. Need at least 100MB available."
    exit 1
fi

# Check permissions
if [ ! -w "$HOME" ]; then
    log_error "Cannot write to home directory: $HOME"
    exit 1
fi

log_success "Pre-flight checks passed"
echo

# Step 2: Configuration Wizard
log_step "Step 2/6: Configuration Wizard"
show_progress 2 6 "Gathering configuration preferences..."

echo "Let's configure your SQLite Memory MCP setup."
echo

# Database location
echo -e "${BLUE}🗂️  Database Configuration${NC}"
DEFAULT_DB="$HOME/.claude/memory/claude_memory.db"
echo "Where would you like to store the memory database?"
echo "Default: $DEFAULT_DB"
read -p "Database path (press Enter for default): " user_db_path
CLAUDE_MEMORY_DB="${user_db_path:-$DEFAULT_DB}"

# Validate database path
DB_DIR="$(dirname "$CLAUDE_MEMORY_DB")"
if [ ! -d "$DB_DIR" ]; then
    log_info "Creating directory: $DB_DIR"
    mkdir -p "$DB_DIR" || {
        log_error "Failed to create directory: $DB_DIR"
        exit 1
    }
fi

# Scope selection  
echo
echo -e "${BLUE}🌐 Scope Configuration${NC}"
echo "How do you want to use this MCP server?"
echo "1) User scope - Available globally for all your projects"
echo "2) Project scope - Shared with team via .mcp.json (recommended for teams)"
while true; do
    read -p "Choose (1 or 2): " scope_choice
    case $scope_choice in
        1) SETUP_SCOPE="user"; break ;;
        2) SETUP_SCOPE="project"; break ;;
        *) log_warning "Please enter 1 or 2" ;;
    esac
done

# Performance level
echo
echo -e "${BLUE}⚡ Performance Configuration${NC}"
echo "Select performance level:"
echo "1) Conservative - Good for low-power systems (32MB cache)"
echo "2) Balanced - Recommended for most users (64MB cache)" 
echo "3) High Performance - For powerful systems (128MB cache)"
while true; do
    read -p "Choose (1, 2, or 3): " perf_choice
    case $perf_choice in
        1) PERFORMANCE_LEVEL="conservative"; break ;;
        2) PERFORMANCE_LEVEL="balanced"; break ;;
        3) PERFORMANCE_LEVEL="high"; break ;;
        *) log_warning "Please enter 1, 2, or 3" ;;
    esac
done

# Write permissions
echo
echo -e "${BLUE}🔒 Security Configuration${NC}"
echo "Do you want to allow agents to create custom tables and modify data?"
echo "⚠️  This enables more features but reduces security"
while true; do
    read -p "Enable write permissions? (y/N): " write_choice
    case $write_choice in
        [Yy]) ENABLE_WRITES="1"; break ;;
        [Nn]|"") ENABLE_WRITES="0"; break ;;
        *) log_warning "Please enter y or n" ;;
    esac
done

log_success "Configuration completed"
echo

# Step 3: Generate configuration
log_step "Step 3/6: Generating Configuration"
show_progress 3 6 "Creating configuration files..."

# Performance settings based on level
case $PERFORMANCE_LEVEL in
    "conservative")
        CACHE_SIZE_KIB=32768
        MMAP_SIZE_BYTES=134217728  # 128MB
        ;;
    "balanced") 
        CACHE_SIZE_KIB=65536
        MMAP_SIZE_BYTES=268435456  # 256MB
        ;;
    "high")
        CACHE_SIZE_KIB=131072
        MMAP_SIZE_BYTES=536870912  # 512MB
        ;;
esac

# Write settings.env
cat > "$ROOT/config/settings.env" <<EOF
# Enhanced SQLite Memory MCP Configuration
# Generated by interactive setup on $(date)

CLAUDE_MEMORY_DB="$CLAUDE_MEMORY_DB"
MCP_SERVER_NAME="$MCP_SERVER_NAME"

# Performance Settings ($PERFORMANCE_LEVEL level)
BUSY_TIMEOUT_MS=30000
CACHE_SIZE_KIB=$CACHE_SIZE_KIB
MMAP_SIZE_BYTES=$MMAP_SIZE_BYTES
SYNCHRONOUS_LEVEL="NORMAL"
ENABLE_WAL="1"
WAL_AUTOCHECKPOINT=1000

# Memory Management
AUTO_OPTIMIZE_ENABLED="1"
AUTO_OPTIMIZE_INTERVAL_HOURS=4
MEMORY_TIER_PROMOTION_THRESHOLD=50
MEMORY_ARCHIVAL_DAYS=90
MAX_AGENT_TABLES_PER_AGENT=10

# Permissions
ALLOW_WRITES="$ENABLE_WRITES"
ENABLE_PERFORMANCE_MONITORING="1"
EOF

log_success "Configuration generated"

# Step 4: Installation
log_step "Step 4/6: System Installation"
show_progress 4 6 "Installing dependencies and database..."

# Source the configuration
source "$ROOT/config/settings.env"

log_info "Installing system dependencies..."
if ! command -v sqlite3 >/dev/null 2>&1; then
    sudo apt update -y >/dev/null 2>&1
    sudo apt install -y sqlite3 sqlite3-doc libsqlite3-dev build-essential pipx >/dev/null 2>&1
    pipx ensurepath >/dev/null 2>&1
fi

log_info "Installing mcp-server-sqlite..."
export PATH="$HOME/.local/bin:$PATH"
pipx install mcp-server-sqlite >/dev/null 2>&1 || log_warning "mcp-server-sqlite may already be installed"

log_info "Creating database and schema..."
mkdir -p "$(dirname "$CLAUDE_MEMORY_DB")"

# Apply bootstrap
"$ROOT/scripts/install_sqlite_and_mcp.sh" >/dev/null 2>&1 || {
    log_error "Database creation failed"
    exit 1
}

log_success "Installation completed"

# Step 5: MCP Registration  
log_step "Step 5/6: MCP Server Registration"
show_progress 5 6 "Registering MCP server with Claude..."

if [ "$SETUP_SCOPE" = "user" ]; then
    log_info "Registering user-scoped MCP server..."
    "$ROOT/scripts/register_user_scope.sh" >/dev/null 2>&1 || {
        log_error "Failed to register user-scoped MCP server"
        log_info "You can manually run: $ROOT/scripts/register_user_scope.sh"
    }
else
    log_info "Registering project-scoped MCP server..."
    "$ROOT/scripts/register_project_scope.sh" >/dev/null 2>&1 || {
        log_error "Failed to register project-scoped MCP server"  
        log_info "You can manually run: $ROOT/scripts/register_project_scope.sh"
    }
fi

# Update user settings
log_info "Configuring user settings..."
mkdir -p "$HOME/.claude"
SETTINGS="$HOME/.claude/settings.json"

# Ensure directory perms (restrictive)
chmod 700 "$HOME/.claude" || true
mkdir -p "$(dirname "$CLAUDE_MEMORY_DB")"
chmod 700 "$(dirname "$CLAUDE_MEMORY_DB")" || true

merge_settings() {
    # Args: $1 (write_enabled: 0/1)
    local write_enabled="$1"
    local tmpfile
    tmpfile="$(mktemp)"
    if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
        jq \
            --arg db "$CLAUDE_MEMORY_DB" \
            --argjson we "$write_enabled" \
            '(.env.CLAUDE_MEMORY_DB = $db) 
             | (.env.CLAUDE_MEMORY_PERFORMANCE_ENABLED = "1")
             | (.tools.sqlite_memory.performance_monitoring = true)
             | (.tools.sqlite_memory.auto_optimization = true)
             | (.tools.sqlite_memory.memory_tier_management = true)
             | (.tools.sqlite_memory.relationship_tracking = true)
             | (.tools.sqlite_memory.write_enabled = ($we==1))
             | (.permissions.allow += ["mcp__sqlite_memory__read_query",
                                                                 "mcp__sqlite_memory__list_tables",
                                                                 "mcp__sqlite_memory__describe_table",
                                                                 "mcp__sqlite_memory__append_insight"]
                 | .permissions.allow |= unique
                )
             | (if $we==1 then (.permissions.allow += ["mcp__sqlite_memory__write_query","mcp__sqlite_memory__create_table"]) else . end)
             | (.permissions.allow |= unique)
            ' "$SETTINGS" > "$tmpfile" 2>/dev/null || return 1
        mv "$tmpfile" "$SETTINGS"
    else
        # Fallback: overwrite from templates
        if [ "$write_enabled" = "1" ]; then
            cat > "$SETTINGS" <<EOF
{
    "env": {
        "CLAUDE_MEMORY_DB": "$CLAUDE_MEMORY_DB",
        "CLAUDE_MEMORY_PERFORMANCE_ENABLED": "1"
    },
    "permissions": {
        "allow": [
            "mcp__sqlite_memory__read_query",
            "mcp__sqlite_memory__list_tables",
            "mcp__sqlite_memory__describe_table",
            "mcp__sqlite_memory__append_insight",
            "mcp__sqlite_memory__write_query",
            "mcp__sqlite_memory__create_table"
        ]
    },
    "tools": {
        "sqlite_memory": {
            "performance_monitoring": true,
            "auto_optimization": true,
            "memory_tier_management": true,
            "relationship_tracking": true,
            "write_enabled": true
        }
    }
}
EOF
        else
            cp "$ROOT/templates/settings.user.sample.json" "$SETTINGS"
            sed -i "s#/home/REPLACE_ME#${HOME}#g" "$SETTINGS"
        fi
    fi
}

merge_settings "$ENABLE_WRITES" || log_warning "Settings merge failed—fallback may be incomplete"

# Restrict settings file perms
chmod 600 "$SETTINGS" || true
if [ -f "$CLAUDE_MEMORY_DB" ]; then chmod 600 "$CLAUDE_MEMORY_DB" || true; fi

log_success "MCP server registered"

# Step 6: Verification
log_step "Step 6/6: Verification"
show_progress 6 6 "Verifying installation..."

# Test database
if sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" >/dev/null 2>&1; then
    TABLE_COUNT=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
    log_success "Database created with $TABLE_COUNT tables"
else
    log_error "Database verification failed"
    exit 1
fi

# Test MCP connection
log_info "Testing MCP server connection..."
sleep 2  # Give the server a moment to register

if claude mcp list 2>/dev/null | grep -q "$MCP_SERVER_NAME.*✓ Connected"; then
    log_success "MCP server connected successfully"
else
    log_warning "MCP server may need a moment to connect. Try: claude mcp list"
fi

# Final success message
echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗"
echo -e "║                    🎉 Setup Complete! 🎉                     ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}📋 Installation Summary:${NC}"
echo -e "   Database: ${YELLOW}$CLAUDE_MEMORY_DB${NC}"
echo -e "   Scope: ${YELLOW}$SETUP_SCOPE${NC}"
echo -e "   Performance: ${YELLOW}$PERFORMANCE_LEVEL${NC} (${CACHE_SIZE_KIB}KB cache)"
echo -e "   Write Access: ${YELLOW}$([ "$ENABLE_WRITES" = "1" ] && echo "Enabled" || echo "Disabled")${NC}"
echo
echo -e "${CYAN}🧪 Quick Test:${NC}"
echo "   Open Claude Code and try:"
echo -e "   ${YELLOW}/mcp${NC}                     # Check server status"
echo -e "   ${YELLOW}\"Show database health\"${NC}      # Test functionality"
echo
echo -e "${CYAN}🛠️  Management:${NC}"
echo -e "   ${YELLOW}./manage.sh status${NC}        # Check system health"  
echo -e "   ${YELLOW}./manage.sh config${NC}        # Modify configuration"
echo -e "   ${YELLOW}./manage.sh doctor${NC}        # Diagnose issues"
echo
if [ "$SETUP_SCOPE" = "project" ]; then
    echo -e "${CYAN}📝 Next Steps for Team Setup:${NC}"
    echo -e "   ${YELLOW}git add .mcp.json${NC}"
    echo -e "   ${YELLOW}git commit -m \"Add SQLite Memory MCP server\"${NC}"
    echo
fi

echo -e "${GREEN}Happy coding with enhanced memory! 🧠✨${NC}"