#!/bin/bash
# inbox_write.sh — メールボックスへのメッセージ書き込み（排他ロック付き）
# Usage: bash scripts/inbox_write.sh <target_agent> <content> [type] [from]
# Example: bash scripts/inbox_write.sh karo "足軽5号、任務完了" report_received ashigaru5

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"

TOPOLOGY="$SCRIPT_DIR/config/topology.yaml"

# ─── Cross-machine routing ───
# If topology.yaml exists and INBOX_LOCAL_ONLY is not set,
# check if the target agent lives on a remote machine.
# Syntax: get_agent_host <agent_id> → prints host or "local"
get_agent_host() {
    local agent="$1"
    if [ ! -f "$TOPOLOGY" ]; then
        echo "local"
        return
    fi
    # Parse topology.yaml using python3 (macOS-compatible, avoids gawk-only awk syntax)
    # Expected structure:
    #   machines:
    #     - id: mac
    #       host: localhost
    #       agents: [shogun, karo, ashigaru1, ...]
    #     - id: linux
    #       host: 192.168.1.100
    #       ssh_user: ubuntu
    #       repo_path: /home/ubuntu/multi-agent-shogun
    #       agents: [daishogun, ...]
    local result
    result=$(python3 -c "
import yaml, sys
try:
    with open('$TOPOLOGY') as f:
        data = yaml.safe_load(f)
    for m in data.get('machines', []):
        if '$agent' in m.get('agents', []):
            host = m.get('host', 'localhost')
            if host in ('localhost', '127.0.0.1'):
                print('local')
            else:
                user = m.get('ssh_user', '')
                print(user + '@' + host if user else host)
            sys.exit(0)
    print('local')
except Exception:
    print('local')
" 2>/dev/null || echo "local")
    echo "$result"
}

# Route to remote machine if needed
SSH_FALLBACK=0
if [ -z "${INBOX_LOCAL_ONLY:-}" ]; then
    AGENT_HOST=$(get_agent_host "$TARGET")
    if [ "$AGENT_HOST" != "local" ]; then
        # Extract repo_path from topology using python3
        REMOTE_REPO=$(python3 -c "
import yaml, sys
try:
    with open('$TOPOLOGY') as f:
        data = yaml.safe_load(f)
    for m in data.get('machines', []):
        if '$TARGET' in m.get('agents', []):
            print(m.get('repo_path', '~/multi-agent-shogun'))
            sys.exit(0)
    print('~/multi-agent-shogun')
except Exception:
    print('~/multi-agent-shogun')
" 2>/dev/null || echo "~/multi-agent-shogun")
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$AGENT_HOST" \
            "INBOX_LOCAL_ONLY=1 bash ${REMOTE_REPO}/scripts/inbox_write.sh '$TARGET' '$CONTENT' '$TYPE' '$FROM'" \
            2>/dev/null; then
            exit 0
        else
            # SSH failed — write locally then git+notify as fallback
            echo "[inbox_write] SSH failed for $AGENT_HOST, falling back to git+notify" >&2
            SSH_FALLBACK=1
        fi
    fi
fi

INBOX="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
LOCKFILE="${INBOX}.lock"

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$CONTENT" ]; then
    echo "Usage: inbox_write.sh <target_agent> <content> [type] [from]" >&2
    exit 1
fi

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    mkdir -p "$(dirname "$INBOX")"
    echo "messages: []" > "$INBOX"
fi

# Generate unique message ID (timestamp-based)
MSG_ID="msg_$(date +%Y%m%d_%H%M%S)_$(head -c 4 /dev/urandom | xxd -p)"
TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

# Atomic write with mkdir lock (macOS compatible, 3 retries)
# mkdir is atomic on all POSIX systems — replaces Linux-only flock
LOCKDIR="${INBOX}.lockdir"
attempt=0
max_attempts=3

acquire_lock() {
    local max_wait=5
    local waited=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        if [ $waited -ge $max_wait ]; then
            return 1
        fi
        sleep 0.5
        waited=$((waited + 1))
    done
    return 0
}

release_lock() {
    rmdir "$LOCKDIR" 2>/dev/null || true
}

while [ $attempt -lt $max_attempts ]; do
    if acquire_lock; then
        trap 'release_lock' EXIT

        # Add message via python3 (unified YAML handling)
        "$SCRIPT_DIR/.venv/bin/python3" -c "
import yaml, sys

try:
    # Load existing inbox
    with open('$INBOX') as f:
        data = yaml.safe_load(f)

    # Initialize if needed
    if not data:
        data = {}
    if not data.get('messages'):
        data['messages'] = []

    # Add new message
    new_msg = {
        'id': '$MSG_ID',
        'from': '$FROM',
        'timestamp': '$TIMESTAMP',
        'type': '$TYPE',
        'content': '''$CONTENT''',
        'read': False
    }
    data['messages'].append(new_msg)

    # Overflow protection: keep max 50 messages
    if len(data['messages']) > 50:
        msgs = data['messages']
        unread = [m for m in msgs if not m.get('read', False)]
        read = [m for m in msgs if m.get('read', False)]
        # Keep all unread + newest 30 read messages
        data['messages'] = unread + read[-30:]

    # Atomic write: tmp file + rename (prevents partial reads)
    import tempfile, os
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname('$INBOX'), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, '$INBOX')
    except:
        os.unlink(tmp_path)
        raise

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" && { release_lock; exit 0; } || { release_lock; exit 1; }

    else
        # Lock timeout
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_write] Lock timeout for $INBOX (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_write] Failed to acquire lock after $max_attempts attempts for $INBOX" >&2
            exit 1
        fi
    fi
done

# Fallback post-write: git push + notify so remote machine can pull
if [ "$SSH_FALLBACK" = "1" ]; then
    (cd "$SCRIPT_DIR" && \
     git add "queue/inbox/${TARGET}.yaml" 2>/dev/null && \
     git commit -m "sync: inbox ${TARGET}" --no-verify 2>/dev/null && \
     git push origin main 2>/dev/null) || true
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "📬 inbox sync: ${TARGET} ← ${FROM} (git pull required)" 2>/dev/null || true
    bash "$SCRIPT_DIR/scripts/slack_send_channel.sh" shogun "📬 inbox sync: ${TARGET} ← ${FROM}. git pullせよ。" 2>/dev/null || true
fi
