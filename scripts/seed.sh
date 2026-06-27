#!/usr/bin/env bash
# Snow Resorts — idempotent dev seed.
#
# Seeds a demo user (auth + profile) and a small resort catalog with trails/lifts.
# Safe to run repeatedly. Tables are created by each service's Flyway migrations at
# startup, so this script GUARDS every insert with to_regclass(): if a service hasn't
# been started yet its tables are simply skipped (re-run `make seed` afterwards).

set -euo pipefail

PG_CONTAINER="${PG_CONTAINER:-snow-postgres}"
PG_USER="${PG_USER:-snow}"
PG_DB="${PG_DB:-snow_resorts}"

echo "==> Waiting for Postgres (${PG_CONTAINER}) to be ready..."
for i in $(seq 1 30); do
  if docker exec "${PG_CONTAINER}" pg_isready -U "${PG_USER}" -d "${PG_DB}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> Seeding demo data (idempotent)..."
docker exec -i "${PG_CONTAINER}" psql -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${PG_DB}" <<'SQL'
-- Stable demo identity reused across services.
\set demo_user_id '11111111-1111-1111-1111-111111111111'

DO $$
DECLARE
    demo_user_id uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
    -- auth-service: demo credentials (password = "Password123!"), bcrypt via pgcrypto.
    IF to_regclass('auth.users_auth') IS NOT NULL THEN
        INSERT INTO auth.users_auth (id, email, password_hash, enabled, created_at)
        VALUES (demo_user_id, 'demo@snow-resorts.com',
                crypt('Password123!', gen_salt('bf', 10)), true, now())
        ON CONFLICT (email) DO NOTHING;
        RAISE NOTICE 'Seeded auth.users_auth';
    END IF;

    -- user-service: matching profile.
    IF to_regclass('users.profiles') IS NOT NULL THEN
        INSERT INTO users.profiles (user_id, display_name, share_stats, share_location, created_at, updated_at)
        VALUES (demo_user_id, 'Demo Rider', 'friends', 'friends', now(), now())
        ON CONFLICT (user_id) DO NOTHING;
        RAISE NOTICE 'Seeded users.profiles';
    END IF;

    -- resort-service: demo trails/lifts (resort catalog comes from Flyway V2 + V3).
    -- Resolve resort_id by slug — Flyway seeds use random UUIDs, not the legacy fixed ids below.
    IF to_regclass('resorts.trails') IS NOT NULL THEN
        INSERT INTO resorts.trails (id, resort_id, name, difficulty, geom)
        SELECT '33333333-3333-3333-3333-333333333331'::uuid, r.id, 'La Vallée Blanche', 'black',
               ST_SetSRID(ST_GeomFromText('LINESTRING(6.8694 45.9237, 6.8800 45.9100, 6.8900 45.9000)'), 4326)
        FROM resorts.resorts r WHERE r.slug = 'chamonix-mont-blanc'
        ON CONFLICT (id) DO NOTHING;

        INSERT INTO resorts.trails (id, resort_id, name, difficulty, geom)
        SELECT '33333333-3333-3333-3333-333333333332'::uuid, r.id, 'Matterhorn Glacier', 'blue',
               ST_SetSRID(ST_GeomFromText('LINESTRING(7.7491 46.0207, 7.7400 46.0100, 7.7300 46.0000)'), 4326)
        FROM resorts.resorts r WHERE r.slug = 'zermatt'
        ON CONFLICT (id) DO NOTHING;

        INSERT INTO resorts.trails (id, resort_id, name, difficulty, geom)
        SELECT '33333333-3333-3333-3333-333333333333'::uuid, r.id, 'Peak to Creek', 'blue',
               ST_SetSRID(ST_GeomFromText('LINESTRING(-122.9574 50.1163, -122.9700 50.1050, -122.9850 50.0920)'), 4326)
        FROM resorts.resorts r WHERE r.slug = 'whistler-blackcomb'
        ON CONFLICT (id) DO NOTHING;

        RAISE NOTICE 'Seeded resorts.trails (skipped when slug not found yet — re-run after resort-service migrates)';
    END IF;
END $$;
SQL

echo "==> Seed complete."
