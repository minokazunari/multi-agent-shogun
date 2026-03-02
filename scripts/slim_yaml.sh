#!/bin/bash
#
# slim_yaml.sh - YAML slimming wrapper with file locking
#
# Usage: bash slim_yaml.sh <agent_id>
#
# This script acquires an exclusive lock before calling the Python slimmer,
# ensuring no concurrent modifications to YAML files (same pattern as inbox_write.sh).
#

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCK_FILE="${SCRIPT_DIR}/../queue/.slim_yaml.lock"
LOCKDIR="${LOCK_FILE}.lockdir"
LOCK_TIMEOUT=10

# Acquire exclusive lock using mkdir (macOS compatible, replaces Linux-only flock)
waited=0
while ! mkdir "$LOCKDIR" 2>/dev/null; do
    if [ "$waited" -ge "$LOCK_TIMEOUT" ]; then
        echo "Error: Failed to acquire lock within $LOCK_TIMEOUT seconds" >&2
        exit 1
    fi
    sleep 1
    waited=$((waited + 1))
done
trap "rmdir '$LOCKDIR' 2>/dev/null" EXIT

# Call the Python implementation
python3 "$(dirname "$0")/slim_yaml.py" "$@"
exit_code=$?

# Lock is released by EXIT trap
exit "$exit_code"
