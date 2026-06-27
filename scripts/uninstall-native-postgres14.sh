#!/usr/bin/env bash
# Remove the legacy EDB PostgreSQL 14 install (/Library/PostgreSQL/14).
# Requires administrator privileges (sudo / macOS auth dialog).

set -euo pipefail

PLIST="/Library/LaunchDaemons/postgresql-14.plist"
PG_ROOT="/Library/PostgreSQL/14"
UNINSTALLER="${PG_ROOT}/uninstall-postgresql.app/Contents/MacOS/installbuilder.sh"

echo "==> Stopping postgresql-14 service..."
if [ -f "$PLIST" ]; then
  launchctl bootout system "$PLIST" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
fi

if [ -x "${PG_ROOT}/bin/pg_ctl" ] && [ -d "${PG_ROOT}/data" ]; then
  sudo -u postgres "${PG_ROOT}/bin/pg_ctl" stop -D "${PG_ROOT}/data" -m fast 2>/dev/null || true
fi

sleep 2

echo "==> Running official EDB uninstaller (unattended)..."
if [ -x "$UNINSTALLER" ]; then
  "$UNINSTALLER" --mode unattended --unattendedmodeui none || {
    echo "Unattended uninstall failed; removing files manually..."
    rm -rf "$PG_ROOT"
    rm -f "$PLIST"
  }
else
  echo "Uninstaller not found; removing files manually..."
  rm -rf "$PG_ROOT"
  rm -f "$PLIST"
fi

# Remove stale symlinks if any
for link in /usr/local/bin/psql /usr/local/bin/postgres; do
  if [ -L "$link" ] && readlink "$link" | grep -q PostgreSQL/14; then
    rm -f "$link"
  fi
done

echo "==> Verifying port 5432..."
if nc -z 127.0.0.1 5432 >/dev/null 2>&1; then
  echo "WARNING: port 5432 still in use — another process may be listening."
  lsof -nP -iTCP:5432 -sTCP:LISTEN 2>/dev/null || true
else
  echo "OK: port 5432 is free."
fi

if [ -d "$PG_ROOT" ]; then
  echo "WARNING: $PG_ROOT still exists."
else
  echo "OK: $PG_ROOT removed."
fi

echo "==> Done."
