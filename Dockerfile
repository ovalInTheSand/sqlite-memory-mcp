FROM python:3.11-slim

LABEL org.opencontainers.image.source="https://github.com/ovalInTheSand/sqlite-memory-mcp"
LABEL org.opencontainers.image.description="Self-learning agent memory system for MCP with SQLite backend"
LABEL org.opencontainers.image.licenses="MIT"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements*.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Install the package in development mode
RUN pip install -e .

# Create data directory for SQLite database
RUN mkdir -p /data && chmod 755 /data

# Set environment variables
ENV CLAUDE_MEMORY_DB=/data/memory.db
ENV ALLOW_WRITES=1
ENV PYTHONPATH=/app

# Expose port (if needed for future web interface)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "from backend.sqlite_backend import SQLiteBackend; print('OK' if SQLiteBackend('/data/memory.db').health_check()['ok'] else exit(1))" || exit 1

# Default command
CMD ["mem"]