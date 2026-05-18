#!/bin/bash
# Validate every project's docker-compose.yml resolves cleanly via
# `docker compose config --quiet`. Catches: YAML syntax errors, undefined
# anchor refs, missing env_file paths, structural compose errors.
#
# Skipped on hosts that don't have a project's secrets materialized in
# common/secrets/.runtime/ — local development on Mac isn't expected to
# carry decrypted secrets, so a missing .runtime file shouldn't fail
# the lint. We use --no-interpolate to avoid that path entirely; we
# only care about syntax + structural references.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

# Local-only escape hatch: if `docker compose` isn't available (no Docker
# Desktop / Colima / OrbStack on Mac), skip rather than fail. CI always
# has it, so the gate runs there. Users who want strict local checking
# can install the plugin or set REQUIRE_COMPOSE=1.
if ! docker compose version >/dev/null 2>&1; then
    if [ "${REQUIRE_COMPOSE:-0}" = "1" ]; then
        echo "ERROR: 'docker compose' not available; install Docker Desktop / Colima / OrbStack" >&2
        exit 1
    fi
    echo "SKIP: 'docker compose' not available locally (CI will validate)" >&2
    exit 0
fi

rc=0
for compose in */docker-compose.yml; do
    [ -f "$compose" ] || continue
    # --no-interpolate skips env-var substitution; we only validate structure
    if ! docker compose -f "$compose" --project-directory "$(dirname "$compose")" config --no-interpolate --quiet 2>&1; then
        echo "ERROR: docker compose config failed for $compose" >&2
        rc=1
    fi
done

exit "$rc"
