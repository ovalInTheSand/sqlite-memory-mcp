#!/usr/bin/env bash
set -euo pipefail

# Enhanced SQLite Memory MCP - Management Tool
# Provides status monitoring, configuration, maintenance, and diagnostics

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Utility functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_header() { echo -e "${BOLD}${CYAN}$1${NC}"; }

# Get script directory and load config
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$ROOT/config/settings.env"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    echo "Run './setup.sh' first to initialize the system."
    exit 1
fi

source "$CONFIG_FILE"

# Utility functions for data formatting
format_bytes() {
    local bytes=$1
    if [ $bytes -gt 1073741824 ]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc)GB"
    elif [ $bytes -gt 1048576 ]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc)MB"
    elif [ $bytes -gt 1024 ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

format_duration() {
    local seconds=$1
    if [ $seconds -gt 86400 ]; then
        echo "$((seconds / 86400))d $((seconds % 86400 / 3600))h"
    elif [ $seconds -gt 3600 ]; then
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    elif [ $seconds -gt 60 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "${seconds}s"
    fi
}

# Check if database exists
check_database() {
    if [ ! -f "$CLAUDE_MEMORY_DB" ]; then
        log_error "Database not found: $CLAUDE_MEMORY_DB"
        echo "Run './setup.sh' to create the database."
        return 1
    fi
    return 0
}

# Status command - comprehensive system overview
cmd_status() {
    log_header "🔍 SQLite Memory MCP Status Dashboard"
    echo
    
    # System Information
    log_header "📊 System Information"
    echo -e "  Database Path: ${YELLOW}$CLAUDE_MEMORY_DB${NC}"
    echo -e "  MCP Server: ${YELLOW}$MCP_SERVER_NAME${NC}"
    
    if check_database; then
        # Database size
        DB_SIZE=$(stat -f%z "$CLAUDE_MEMORY_DB" 2>/dev/null || stat -c%s "$CLAUDE_MEMORY_DB" 2>/dev/null || echo "0")
        echo -e "  Database Size: ${YELLOW}$(format_bytes $DB_SIZE)${NC}"
        
        # Database age
        if command -v stat >/dev/null 2>&1; then
            if stat -f%B "$CLAUDE_MEMORY_DB" >/dev/null 2>&1; then
                # macOS
                DB_CREATED=$(stat -f%B "$CLAUDE_MEMORY_DB")
            else
                # Linux
                DB_CREATED=$(stat -c%Y "$CLAUDE_MEMORY_DB")
            fi
            DB_AGE=$(($(date +%s) - DB_CREATED))
            echo -e "  Database Age: ${YELLOW}$(format_duration $DB_AGE)${NC}"
        fi
    else
        return 1
    fi
    echo
    
    # Database Health
    log_header "🏥 Database Health"
    
    # Basic integrity check
    if sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA integrity_check;" | head -1 | grep -q "ok"; then
        echo -e "  Integrity: ${GREEN}✅ OK${NC}"
    else
        echo -e "  Integrity: ${RED}❌ CORRUPTED${NC}"
    fi
    
    # Configuration check
    JOURNAL_MODE=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA journal_mode;" 2>/dev/null || echo "unknown")
    FOREIGN_KEYS=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA foreign_keys;" 2>/dev/null || echo "0")
    
    echo -e "  Journal Mode: ${YELLOW}$JOURNAL_MODE${NC}"
    echo -e "  Foreign Keys: ${YELLOW}$([ "$FOREIGN_KEYS" = "1" ] && echo "Enabled" || echo "Disabled")${NC}"
    
    # Table counts
    TABLE_COUNT=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>/dev/null || echo "0")
    VIEW_COUNT=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='view';" 2>/dev/null || echo "0")
    
    echo -e "  Tables: ${YELLOW}$TABLE_COUNT${NC}"
    echo -e "  Views: ${YELLOW}$VIEW_COUNT${NC}"
    echo
    
    # Memory Statistics
    log_header "🧠 Memory Statistics"
    
    TOTAL_MEMORIES=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM memory;" 2>/dev/null || echo "0")
    echo -e "  Total Memories: ${YELLOW}$TOTAL_MEMORIES${NC}"
    
    if [ "$TOTAL_MEMORIES" -gt 0 ]; then
        # Memory by tier
        sqlite3 "$CLAUDE_MEMORY_DB" "
            SELECT '  ' || memory_tier || ': ' || COUNT(*) 
            FROM memory 
            GROUP BY memory_tier 
            ORDER BY 
                CASE memory_tier 
                    WHEN 'hot' THEN 1 
                    WHEN 'warm' THEN 2 
                    WHEN 'cold' THEN 3 
                    WHEN 'archived' THEN 4 
                    ELSE 5 
                END;
        " 2>/dev/null | while read line; do
            echo -e "${YELLOW}$line${NC}"
        done
        
        # Recent activity
        RECENT_MEMORIES=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM memory WHERE created_at >= datetime('now', '-24 hours');" 2>/dev/null || echo "0")
        echo -e "  Created Today: ${YELLOW}$RECENT_MEMORIES${NC}"
    fi
    echo
    
    # Agent Information  
    log_header "🤖 Agent Information"
    
    ACTIVE_AGENTS=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM agents WHERE active = 1;" 2>/dev/null || echo "0")
    echo -e "  Active Agents: ${YELLOW}$ACTIVE_AGENTS${NC}"
    
    if [ "$ACTIVE_AGENTS" -gt 0 ]; then
        CUSTOM_TABLES=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM agent_tables;" 2>/dev/null || echo "0")
        echo -e "  Custom Tables: ${YELLOW}$CUSTOM_TABLES${NC}"
    fi
    echo
    
    # MCP Server Status
    log_header "🔗 MCP Server Status"
    
    if command -v claude >/dev/null 2>&1; then
        if claude mcp list 2>/dev/null | grep -q "$MCP_SERVER_NAME.*✓ Connected"; then
            echo -e "  Connection: ${GREEN}✅ Connected${NC}"
        else
            echo -e "  Connection: ${RED}❌ Disconnected${NC}"
            log_warning "Try running: claude mcp list"
        fi
    else
        log_warning "Claude CLI not found - cannot check MCP status"
    fi
    echo
    
    # Performance Insights
    if [ "$TOTAL_MEMORIES" -gt 100 ]; then
        log_header "⚡ Performance Insights"
        
        # Check for optimization opportunities
        COLD_MEMORIES=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM memory WHERE memory_tier = 'cold' AND access_count > 25;" 2>/dev/null || echo "0")
        if [ "$COLD_MEMORIES" -gt 0 ]; then
            log_warning "$COLD_MEMORIES memories may benefit from promotion to warm tier"
        fi
        
        # Check for archival candidates
        ARCHIVAL_CANDIDATES=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM memory WHERE datetime(last_accessed, '+90 days') < datetime('now') AND memory_tier != 'archived';" 2>/dev/null || echo "0")
        if [ "$ARCHIVAL_CANDIDATES" -gt 0 ]; then
            log_info "$ARCHIVAL_CANDIDATES memories are candidates for archival"
        fi
        
        echo -e "  Run ${YELLOW}./manage.sh optimize${NC} for performance improvements"
        echo
    fi
}

# Config command - manage configuration
cmd_config() {
    log_header "⚙️  Configuration Management"
    echo
    
    echo "Current configuration:"
    echo -e "  Database: ${YELLOW}$CLAUDE_MEMORY_DB${NC}"
    echo -e "  Cache Size: ${YELLOW}${CACHE_SIZE_KIB}KB${NC}"
    echo -e "  Memory Mapping: ${YELLOW}$(format_bytes $MMAP_SIZE_BYTES)${NC}"
    echo -e "  Write Access: ${YELLOW}$([ "$ALLOW_WRITES" = "1" ] && echo "Enabled" || echo "Disabled")${NC}"
    echo
    
    while true; do
        echo "What would you like to configure?"
        echo "1) Performance settings"
        echo "2) Memory management thresholds"
        echo "3) Enable/disable write access"
        echo "4) View current settings file"
        echo "5) Reset to defaults"
        echo "6) Back to main menu"
        
        read -p "Choose (1-6): " config_choice
        case $config_choice in
            1) configure_performance ;;
            2) configure_memory ;;
            3) configure_permissions ;;
            4) cat "$CONFIG_FILE" ;;
            5) reset_config ;;
            6) break ;;
            *) log_warning "Please enter 1-6" ;;
        esac
        echo
    done
}

configure_performance() {
    echo
    log_header "⚡ Performance Configuration"
    echo "Current cache size: ${CACHE_SIZE_KIB}KB"
    echo
    echo "Select performance level:"
    echo "1) Conservative (32MB cache) - Low power systems"
    echo "2) Balanced (64MB cache) - Most systems" 
    echo "3) High Performance (128MB cache) - Powerful systems"
    echo "4) Custom - Enter specific values"
    
    read -p "Choose (1-4): " perf_choice
    case $perf_choice in
        1) new_cache=32768; new_mmap=134217728 ;;
        2) new_cache=65536; new_mmap=268435456 ;;
        3) new_cache=131072; new_mmap=536870912 ;;
        4) 
            read -p "Cache size in KB: " new_cache
            read -p "Memory mapping in bytes: " new_mmap
            ;;
        *) log_warning "Invalid choice"; return ;;
    esac
    
    sed -i "s/CACHE_SIZE_KIB=.*/CACHE_SIZE_KIB=$new_cache/" "$CONFIG_FILE"
    sed -i "s/MMAP_SIZE_BYTES=.*/MMAP_SIZE_BYTES=$new_mmap/" "$CONFIG_FILE"
    
    log_success "Performance settings updated"
    log_info "Restart Claude Code for changes to take effect"
}

configure_memory() {
    echo
    log_header "🧠 Memory Management Configuration"
    echo "Current settings:"
    echo "  Promotion threshold: $MEMORY_TIER_PROMOTION_THRESHOLD accesses"
    echo "  Archival after: $MEMORY_ARCHIVAL_DAYS days"
    echo "  Max agent tables: $MAX_AGENT_TABLES_PER_AGENT"
    echo
    
    read -p "New promotion threshold (current: $MEMORY_TIER_PROMOTION_THRESHOLD): " new_threshold
    new_threshold=${new_threshold:-$MEMORY_TIER_PROMOTION_THRESHOLD}
    
    read -p "New archival days (current: $MEMORY_ARCHIVAL_DAYS): " new_archival
    new_archival=${new_archival:-$MEMORY_ARCHIVAL_DAYS}
    
    read -p "Max agent tables (current: $MAX_AGENT_TABLES_PER_AGENT): " new_max_tables
    new_max_tables=${new_max_tables:-$MAX_AGENT_TABLES_PER_AGENT}
    
    sed -i "s/MEMORY_TIER_PROMOTION_THRESHOLD=.*/MEMORY_TIER_PROMOTION_THRESHOLD=$new_threshold/" "$CONFIG_FILE"
    sed -i "s/MEMORY_ARCHIVAL_DAYS=.*/MEMORY_ARCHIVAL_DAYS=$new_archival/" "$CONFIG_FILE"
    sed -i "s/MAX_AGENT_TABLES_PER_AGENT=.*/MAX_AGENT_TABLES_PER_AGENT=$new_max_tables/" "$CONFIG_FILE"
    
    log_success "Memory management settings updated"
}

configure_permissions() {
    echo
    log_header "🔒 Permission Configuration"
    echo "Current write access: $([ "$ALLOW_WRITES" = "1" ] && echo "Enabled" || echo "Disabled")"
    echo
    
    while true; do
        read -p "Enable write access? (y/N): " write_choice
        case $write_choice in
            [Yy]) new_writes="1"; break ;;
            [Nn]|"") new_writes="0"; break ;;
            *) log_warning "Please enter y or n" ;;
        esac
    done
    
    sed -i "s/ALLOW_WRITES=.*/ALLOW_WRITES=$new_writes/" "$CONFIG_FILE"
    
    # Update user settings
    SETTINGS="$HOME/.claude/settings.json"
    if [ -f "$SETTINGS" ]; then
        if [ "$new_writes" = "1" ]; then
            # Add write permissions if not present
            if ! grep -q "mcp__sqlite_memory__write_query" "$SETTINGS"; then
                log_info "Adding write permissions to Claude settings..."
                # This is a simplified approach - in practice you'd want JSON manipulation
                log_warning "Please manually add write permissions to $SETTINGS"
                echo "Add these to permissions.allow array:"
                echo "  \"mcp__sqlite_memory__write_query\","
                echo "  \"mcp__sqlite_memory__create_table\""
            fi
        else
            log_info "Write permissions disabled in configuration"
            log_warning "You may want to remove write permissions from $SETTINGS"
        fi
    fi
    
    log_success "Permission settings updated"
}

reset_config() {
    echo
    log_header "🔄 Reset Configuration"
    log_warning "This will reset all settings to defaults"
    read -p "Are you sure? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy] ]]; then
        cp "$ROOT/config/settings.env.example" "$CONFIG_FILE" 2>/dev/null || {
            log_error "Cannot find settings.env.example"
            return 1
        }
        log_success "Configuration reset to defaults"
        log_info "You may need to run './setup.sh' to reconfigure"
    fi
}

# Optimize command - run maintenance tasks
cmd_optimize() {
    log_header "⚡ Database Optimization"
    echo
    
    if ! check_database; then
        return 1
    fi
    
    log_info "Running database optimization..."
    
    # Analyze tables for query planner
    echo -n "  Analyzing tables... "
    sqlite3 "$CLAUDE_MEMORY_DB" "ANALYZE;" 2>/dev/null && echo -e "${GREEN}✅${NC}" || echo -e "${RED}❌${NC}"
    
    # Check for fragmentation
    echo -n "  Checking fragmentation... "
    FREELIST=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA freelist_count;" 2>/dev/null || echo "0")
    PAGECOUNT=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA page_count;" 2>/dev/null || echo "1")
    FRAGMENTATION=$((FREELIST * 100 / PAGECOUNT))
    
    if [ $FRAGMENTATION -gt 10 ]; then
        echo -e "${YELLOW}$FRAGMENTATION% fragmented${NC}"
        log_info "Running VACUUM to defragment..."
        sqlite3 "$CLAUDE_MEMORY_DB" "VACUUM;" 2>/dev/null && log_success "VACUUM completed" || log_error "VACUUM failed"
    else
        echo -e "${GREEN}$FRAGMENTATION% fragmented${NC}"
    fi
    
    # WAL checkpoint
    echo -n "  Checkpointing WAL... "
    sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA wal_checkpoint;" >/dev/null 2>&1 && echo -e "${GREEN}✅${NC}" || echo -e "${RED}❌${NC}"
    
    # Archive old memories
    if [ "$TOTAL_MEMORIES" -gt 0 ]; then
        echo -n "  Archiving old memories... "
        ARCHIVED=$(sqlite3 "$CLAUDE_MEMORY_DB" "
            SELECT COUNT(*) FROM memory 
            WHERE datetime(last_accessed, '+${MEMORY_ARCHIVAL_DAYS:-90} days') < datetime('now') 
              AND memory_tier != 'archived' 
              AND access_count < 3;
        " 2>/dev/null || echo "0")
        
        if [ "$ARCHIVED" -gt 0 ]; then
            sqlite3 "$CLAUDE_MEMORY_DB" "
                UPDATE memory 
                SET memory_tier = 'archived' 
                WHERE datetime(last_accessed, '+${MEMORY_ARCHIVAL_DAYS:-90} days') < datetime('now') 
                  AND memory_tier != 'archived' 
                  AND access_count < 3;
            " 2>/dev/null && echo -e "${GREEN}Archived $ARCHIVED memories${NC}" || echo -e "${RED}❌${NC}"
        else
            echo -e "${GREEN}No memories to archive${NC}"
        fi
    fi
    
    log_success "Optimization completed"
    echo
}

# Backup command
cmd_backup() {
    log_header "💾 Database Backup"
    echo
    
    if ! check_database; then
        return 1
    fi
    
    BACKUP_DIR="$HOME/.claude/memory/backups"
    mkdir -p "$BACKUP_DIR"
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/claude_memory_$TIMESTAMP.db"
    
    log_info "Creating backup..."
    echo "  Source: $CLAUDE_MEMORY_DB"
    echo "  Destination: $BACKUP_FILE"
    
    if sqlite3 "$CLAUDE_MEMORY_DB" ".backup '$BACKUP_FILE'" 2>/dev/null; then
        BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null || echo "0")
        log_success "Backup created: $(format_bytes $BACKUP_SIZE)"
        
        # Verify backup integrity
        if sqlite3 "$BACKUP_FILE" "PRAGMA integrity_check;" | head -1 | grep -q "ok"; then
            log_success "Backup integrity verified"
        else
            log_error "Backup integrity check failed"
        fi
    else
        log_error "Backup failed"
        return 1
    fi
    
    # Cleanup old backups (keep last 10)
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/claude_memory_*.db 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 10 ]; then
        log_info "Cleaning up old backups..."
        ls -1t "$BACKUP_DIR"/claude_memory_*.db | tail -n +11 | xargs rm -f
        log_success "Old backups cleaned up"
    fi
    
    echo
}

# Doctor command - comprehensive diagnostics
cmd_doctor() {
    log_header "🩺 System Diagnostics"
    echo
    
    local issues=0
    local warnings=0
    
    # Check 1: Database existence and accessibility
    echo -n "📁 Database file... "
    if [ -f "$CLAUDE_MEMORY_DB" ]; then
        if [ -r "$CLAUDE_MEMORY_DB" ] && [ -w "$CLAUDE_MEMORY_DB" ]; then
            echo -e "${GREEN}✅ OK${NC}"
        else
            echo -e "${RED}❌ Permission issues${NC}"
            ((issues++))
        fi
    else
        echo -e "${RED}❌ Not found${NC}"
        echo "  Run './setup.sh' to create the database"
        ((issues++))
    fi
    
    # Check 2: Database integrity
    echo -n "🔍 Database integrity... "
    if check_database && sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA integrity_check;" | head -1 | grep -q "ok"; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ Corrupted${NC}"
        echo "  Try restoring from backup or recreate database"
        ((issues++))
    fi
    
    # Check 3: Required tables
    echo -n "📊 Schema completeness... "
    if check_database; then
        EXPECTED_TABLES=25  # Based on our enhanced schema
        ACTUAL_TABLES=$(sqlite3 "$CLAUDE_MEMORY_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>/dev/null || echo "0")
        if [ "$ACTUAL_TABLES" -ge "$EXPECTED_TABLES" ]; then
            echo -e "${GREEN}✅ OK ($ACTUAL_TABLES tables)${NC}"
        else
            echo -e "${YELLOW}⚠️  Incomplete ($ACTUAL_TABLES/$EXPECTED_TABLES tables)${NC}"
            echo "  Database may need schema update"
            ((warnings++))
        fi
    else
        echo -e "${RED}❌ Cannot check${NC}"
        ((issues++))
    fi
    
    # Check 4: SQLite version and features
    echo -n "🏗️  SQLite version... "
    SQLITE_VERSION=$(sqlite3 --version | cut -d' ' -f1)
    SQLITE_MAJOR=$(echo "$SQLITE_VERSION" | cut -d'.' -f1)
    SQLITE_MINOR=$(echo "$SQLITE_VERSION" | cut -d'.' -f2)
    
    if [ "$SQLITE_MAJOR" -gt 3 ] || ([ "$SQLITE_MAJOR" -eq 3 ] && [ "$SQLITE_MINOR" -ge 35 ]); then
        echo -e "${GREEN}✅ OK ($SQLITE_VERSION)${NC}"
        
        # Check for critical features
        if ! sqlite3 :memory: "SELECT sqlite_compileoption_used('ENABLE_FTS5');" | grep -q 1 2>/dev/null; then
            echo -e "    ${YELLOW}⚠️  FTS5 not available - search features limited${NC}"
            ((warnings++))
        fi
        
        if ! sqlite3 :memory: "SELECT sqlite_compileoption_used('ENABLE_JSON1');" | grep -q 1 2>/dev/null; then
            echo -e "    ${YELLOW}⚠️  JSON1 not available - some features may not work${NC}"
            ((warnings++))
        fi
    else
        echo -e "${YELLOW}⚠️  Old version ($SQLITE_VERSION)${NC}"
        echo "  Consider updating: sudo apt install sqlite3"
        echo "  Old versions may lack required FTS5 and JSON1 support"
        ((warnings++))
    fi
    
    # Check 5: MCP server availability
    echo -n "🔗 MCP server... "
    if command -v claude >/dev/null 2>&1; then
        if claude mcp list 2>/dev/null | grep -q "$MCP_SERVER_NAME"; then
            if claude mcp list 2>/dev/null | grep -q "$MCP_SERVER_NAME.*✓ Connected"; then
                echo -e "${GREEN}✅ Connected${NC}"
            else
                echo -e "${YELLOW}⚠️  Registered but not connected${NC}"
                echo "  Try: claude mcp list"
                ((warnings++))
            fi
        else
            echo -e "${RED}❌ Not registered${NC}"
            echo "  Run registration script: ./scripts/register_user_scope.sh"
            ((issues++))
        fi
    else
        echo -e "${RED}❌ Claude CLI not found${NC}"
        echo "  Install Claude CLI to use MCP features"
        ((issues++))
    fi
    
    # Check 6: Permissions
    echo -n "🔐 User settings... "
    USER_SETTINGS="$HOME/.claude/settings.json"
    if [ -f "$USER_SETTINGS" ]; then
        if grep -q "sqlite_memory" "$USER_SETTINGS" 2>/dev/null; then
            echo -e "${GREEN}✅ Configured${NC}"
        else
            echo -e "${YELLOW}⚠️  May need configuration${NC}"
            ((warnings++))
        fi
    else
        echo -e "${YELLOW}⚠️  Settings file not found${NC}"
        echo "  Run './setup.sh' to create user settings"
        ((warnings++))
    fi
    
    # Check 7: Disk space
    echo -n "💾 Disk space... "
    if command -v df >/dev/null 2>&1; then
        AVAILABLE_MB=$(df -m "$HOME" | awk 'NR==2 {print $4}')
        if [ "$AVAILABLE_MB" -gt 100 ]; then
            echo -e "${GREEN}✅ OK (${AVAILABLE_MB}MB available)${NC}"
        else
            echo -e "${YELLOW}⚠️  Low space (${AVAILABLE_MB}MB available)${NC}"
            echo "  Consider cleaning up or expanding disk space"
            ((warnings++))
        fi
    else
        echo -e "${YELLOW}⚠️  Cannot check${NC}"
        ((warnings++))
    fi
    
    # Check 8: Performance indicators
    if check_database && [ "$TOTAL_MEMORIES" -gt 0 ]; then
        echo -n "⚡ Performance health... "
        
        # Check fragmentation
        FREELIST=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA freelist_count;" 2>/dev/null || echo "0")
        PAGECOUNT=$(sqlite3 "$CLAUDE_MEMORY_DB" "PRAGMA page_count;" 2>/dev/null || echo "1")
        FRAGMENTATION=$((FREELIST * 100 / PAGECOUNT))
        
        if [ $FRAGMENTATION -lt 10 ]; then
            echo -e "${GREEN}✅ OK (${FRAGMENTATION}% fragmented)${NC}"
        else
            echo -e "${YELLOW}⚠️  High fragmentation (${FRAGMENTATION}%)${NC}"
            echo "  Run './manage.sh optimize' to defragment"
            ((warnings++))
        fi
    fi
    
    # Summary
    echo
    log_header "📋 Diagnostic Summary"
    
    if [ $issues -eq 0 ] && [ $warnings -eq 0 ]; then
        log_success "All systems healthy! ✨"
    elif [ $issues -eq 0 ]; then
        log_warning "$warnings warning(s) found - system functional but could be improved"
    else
        log_error "$issues critical issue(s) and $warnings warning(s) found"
        echo "Please address critical issues for proper functionality."
    fi
    
    echo
}

# Clean command - cleanup operations
cmd_clean() {
    log_header "🧹 Cleanup Operations"
    echo
    
    if ! check_database; then
        return 1
    fi
    
    echo "What would you like to clean?"
    echo "1) Archive old memories (90+ days inactive)"
    echo "2) Remove unused agent tables"  
    echo "3) Clean backup files (keep last 10)"
    echo "4) Vacuum database (defragment)"
    echo "5) All of the above"
    
    read -p "Choose (1-5): " clean_choice
    
    case $clean_choice in
        1|5) clean_old_memories ;;
    esac
    
    case $clean_choice in
        2|5) clean_agent_tables ;;
    esac
    
    case $clean_choice in
        3|5) clean_backups ;;
    esac
    
    case $clean_choice in
        4|5) clean_vacuum ;;
    esac
}

clean_old_memories() {
    echo -n "🗂️  Archiving old memories... "
    CANDIDATES=$(sqlite3 "$CLAUDE_MEMORY_DB" "
        SELECT COUNT(*) FROM memory 
        WHERE datetime(last_accessed, '+90 days') < datetime('now') 
          AND memory_tier != 'archived' 
          AND access_count < 3;
    " 2>/dev/null || echo "0")
    
    if [ "$CANDIDATES" -gt 0 ]; then
        sqlite3 "$CLAUDE_MEMORY_DB" "
            UPDATE memory 
            SET memory_tier = 'archived' 
            WHERE datetime(last_accessed, '+90 days') < datetime('now') 
              AND memory_tier != 'archived' 
              AND access_count < 3;
        " 2>/dev/null && echo -e "${GREEN}Archived $CANDIDATES memories${NC}" || echo -e "${RED}❌${NC}"
    else
        echo -e "${GREEN}No memories to archive${NC}"
    fi
}

clean_agent_tables() {
    echo -n "🤖 Cleaning agent tables... "
    UNUSED_TABLES=$(sqlite3 "$CLAUDE_MEMORY_DB" "
        SELECT COUNT(*) FROM agent_tables 
        WHERE last_used < datetime('now', '-30 days') 
          AND usage_count < 10;
    " 2>/dev/null || echo "0")
    
    if [ "$UNUSED_TABLES" -gt 0 ]; then
        log_warning "$UNUSED_TABLES unused tables found"
        echo "This requires manual review - use SQL queries to inspect and remove"
    else
        echo -e "${GREEN}No unused tables found${NC}"
    fi
}

clean_backups() {
    echo -n "💾 Cleaning old backups... "
    BACKUP_DIR="$HOME/.claude/memory/backups"
    if [ -d "$BACKUP_DIR" ]; then
        BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/claude_memory_*.db 2>/dev/null | wc -l)
        if [ "$BACKUP_COUNT" -gt 10 ]; then
            REMOVED=$((BACKUP_COUNT - 10))
            ls -1t "$BACKUP_DIR"/claude_memory_*.db | tail -n +11 | xargs rm -f
            echo -e "${GREEN}Removed $REMOVED old backups${NC}"
        else
            echo -e "${GREEN}No cleanup needed${NC}"
        fi
    else
        echo -e "${GREEN}No backup directory${NC}"
    fi
}

clean_vacuum() {
    echo -n "🗜️  Vacuuming database... "
    if sqlite3 "$CLAUDE_MEMORY_DB" "VACUUM;" 2>/dev/null; then
        echo -e "${GREEN}✅ Completed${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
}

# Help command
cmd_help() {
    log_header "📖 SQLite Memory MCP Management Tool"
    echo
    echo -e "${BOLD}USAGE:${NC}"
    echo "  ./manage.sh <command>"
    echo
    echo -e "${BOLD}COMMANDS:${NC}"
    echo -e "  ${YELLOW}status${NC}     Show comprehensive system status and health"
    echo -e "  ${YELLOW}config${NC}     Manage configuration settings"
    echo -e "  ${YELLOW}optimize${NC}   Run database optimization and maintenance"
    echo -e "  ${YELLOW}backup${NC}     Create database backup with verification"
    echo -e "  ${YELLOW}clean${NC}      Clean up old data and optimize storage"
    echo -e "  ${YELLOW}doctor${NC}     Run comprehensive system diagnostics"
    echo -e "  ${YELLOW}help${NC}       Show this help message"
    echo
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo -e "  ${CYAN}./manage.sh status${NC}     # Check system health"
    echo -e "  ${CYAN}./manage.sh doctor${NC}     # Diagnose issues"
    echo -e "  ${CYAN}./manage.sh optimize${NC}   # Improve performance"
    echo -e "  ${CYAN}./manage.sh backup${NC}     # Create backup"
    echo
}

# Main command dispatcher
main() {
    local command=${1:-help}
    
    case $command in
        status|s) cmd_status ;;
        config|c) cmd_config ;;
        optimize|o) cmd_optimize ;;
        backup|b) cmd_backup ;;
        clean) cmd_clean ;;
        doctor|d) cmd_doctor ;;
        help|h|-h|--help) cmd_help ;;
        *)
            log_error "Unknown command: $command"
            echo "Run './manage.sh help' for available commands."
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"