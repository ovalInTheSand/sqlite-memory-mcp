# Enhanced SQLite Memory MCP — Overview

## **Core Architecture**
- **User scope**: Global MCP definition available to all projects
- **Project scope**: `.mcp.json` committed so teams share the server config  
- **Enhanced WAL mode**: Persistent journal with autocheckpoint for optimal concurrency
- **STRICT schema**: Type safety with FTS5 external-content for fast search
- **Multi-tier memory**: Hot/warm/cold/archived automatic tiering based on usage

## **Key Enhancements**
- **Performance optimized**: SQLite 3.46.0+ features with intelligent PRAGMA settings
- **Memory relationship graph**: Semantic linking between memories with confidence scores
- **Agent-specific tables**: Dynamic schema without complex migrations
- **Performance monitoring**: Query metrics, health monitoring, optimization suggestions
- **Smart archival**: Automatic cleanup of old, unused memories

## **Production Ready Features**
- **Resource quotas**: Prevent runaway agent table creation
- **Health monitoring**: Real-time database performance and optimization alerts
- **Automatic maintenance**: Self-optimizing with ANALYZE, VACUUM, and index tuning
- **Hot backups**: Non-blocking backup capability during operation
- **Concurrent access**: Optimized for multiple agents with proper locking
