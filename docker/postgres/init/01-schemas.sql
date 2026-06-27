-- Snow Resorts — local Postgres bootstrap.
-- One database (snow_resorts), one logical schema per service (database-per-schema pattern).
-- Flyway then owns the tables inside each schema at service startup.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS users;
CREATE SCHEMA IF NOT EXISTS resorts;
CREATE SCHEMA IF NOT EXISTS location;
CREATE SCHEMA IF NOT EXISTS activity;

-- The single dev user owns every schema; in AWS each service gets a least-privilege role.
GRANT ALL ON SCHEMA auth, users, resorts, location, activity TO snow;

-- PostGIS types (geometry, geography) live in `public`. Each service sets
-- currentSchema to its own schema, so include `public` in the search path.
ALTER DATABASE snow_resorts SET search_path TO public, auth, users, resorts, location, activity;
ALTER ROLE snow SET search_path TO public, auth, users, resorts, location, activity;
