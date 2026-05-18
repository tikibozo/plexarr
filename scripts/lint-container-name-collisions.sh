#!/bin/bash
# Container_name collision linter — Phase 2 stage (within-file uniqueness only).
#
# Each docker-compose.yml may declare multiple services, and `container_name:`
# values within that ONE file must be unique. This is an always-true invariant
# — duplicates are already a compose error at runtime — so the lint failing
# means someone introduced an actual duplicate.
#
# Phase 4 will flip this to cross-project mode after the known mysql-server
# collision (mon/ on cloud-server vs monproxy/ on server) is resolved by
# renaming monproxy's mysql-server to monitor-mysql during the trust-zone
# restructure.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

rc=0
for compose in */docker-compose.yml; do
    [ -f "$compose" ] || continue
    dups=$(grep -E '^\s*container_name:' "$compose" \
        | sed -E 's/^\s*container_name:\s*//' \
        | tr -d '"' \
        | sort | uniq -d)
    if [ -n "$dups" ]; then
        echo "ERROR: duplicate container_name in $compose:" >&2
        echo "$dups" | sed 's/^/  /' >&2
        rc=1
    fi
done

exit "$rc"
