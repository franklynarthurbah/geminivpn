-- =============================================================================
-- GeminiVPN PostgreSQL Init Script
-- Runs once when the container is first created
-- =============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pg_crypto for hashing (optional, bcrypt handled in app)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Grant privileges to app user (already created by POSTGRES_USER env var)
GRANT ALL PRIVILEGES ON DATABASE geminivpn TO geminivpn;

-- Set timezone
SET timezone = 'UTC';
