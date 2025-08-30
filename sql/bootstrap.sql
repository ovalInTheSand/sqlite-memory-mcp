-- =============== CORE PRAGMAS (Enhanced for Performance) ===============
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=30000;         -- reduces SQLITE_BUSY under light contention
PRAGMA cache_size=-65536;          -- negative => KiB units, ~64MB cache
PRAGMA temp_store=MEMORY;          -- store temp tables/indexes in RAM
PRAGMA mmap_size=268435456;        -- 256MB memory mapping
PRAGMA synchronous=NORMAL;         -- good balance with WAL
PRAGMA journal_mode=WAL;           -- WAL persists on the DB file
PRAGMA wal_autocheckpoint=1000;    -- checkpoint every 1000 pages
PRAGMA user_version=2;             -- version 2 for enhanced schema
PRAGMA application_id=0x434C4D50;  -- 'CLMP' marker

-- =============== OPTIMIZATION SETTINGS ===============
-- Enable query planner optimizations
PRAGMA optimize;                   -- Update statistics
PRAGMA analysis_limit=1000;        -- Reasonable analysis limit for large DBs

-- =============== PERFORMANCE MONITORING SETUP ===============
-- These will be populated by the enhanced schema
-- Initial optimization log entry will be created by schema.sql
