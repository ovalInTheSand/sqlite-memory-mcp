# 🚀 Quick Start Guide

Get your Enhanced SQLite Memory MCP up and running in **2 minutes**!

## **One-Command Setup**

```bash
# Clone the repository
git clone <your-repo-url>
cd sqlite-memory-mcp

# Run interactive setup (handles everything!)
./setup.sh
```

That's it! The interactive installer will:
- ✅ Guide you through configuration choices
- ✅ Install all dependencies automatically  
- ✅ Create and optimize the database
- ✅ Register the MCP server with Claude
- ✅ Set up permissions and security

## **What the Setup Asks**

### **1. Database Location** 
- **Default**: `$HOME/.claude/memory/claude_memory.db`
- **Custom**: Enter your preferred path

### **2. Usage Scope**
- **User scope**: Available globally for all your projects
- **Project scope**: Shared with team via `.mcp.json` (better for teams)

### **3. Performance Level**
- **Conservative**: 32MB cache (low-power systems)
- **Balanced**: 64MB cache (most users) ⭐ **Recommended**
- **High Performance**: 128MB cache (powerful systems)

### **4. Security Level**
- **Read-only**: Safer, agents can only read data ⭐ **Recommended**
- **Read-write**: Agents can create tables and modify data

## **Verify It's Working**

Open Claude Code and test:
```
/mcp                          # Check server status
"Show database health"         # Test basic functionality
"List all memory entries"      # Test database access
```

You should see your `sqlite_memory` server connected! ✅

## **Daily Usage Commands**

```bash
# Check system health
./manage.sh status

# Run maintenance/optimization  
./manage.sh optimize

# Create backup
./manage.sh backup

# Diagnose any issues
./manage.sh doctor

# Change configuration
./manage.sh config
```

## **Need Help?**

- **Issues**: Run `./manage.sh doctor` for diagnostics
- **Configuration**: Run `./manage.sh config` to adjust settings
- **Documentation**: See [README.md](README.md) for comprehensive guide

## **What You Get**

🧠 **Intelligent Memory System**
- Automatic tier management (hot/warm/cold/archived)
- Memory relationships with confidence scoring
- Smart access tracking and optimization

⚡ **High Performance**  
- SQLite 3.46.0+ optimizations
- WAL mode with intelligent checkpointing
- Memory-mapped I/O and smart caching

🤖 **Agent-Aware**
- Custom table creation per agent
- Resource quotas and usage tracking  
- Role-based memory scoping

📊 **Production Ready**
- Health monitoring and alerts
- Automatic backup and recovery
- Comprehensive diagnostics

**Happy coding with enhanced memory! 🧠✨**