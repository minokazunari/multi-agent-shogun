#!/usr/bin/env bash
# SessionStart hook: Identify agent role from tmux and load instructions file
# This ensures the role's .md file is always read at startup, compaction, or /clear recovery.
# Exception: ashigaru skips on /clear recovery (cost saving per CLAUDE.md rules).

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Read hook input from stdin (JSON with session info)
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('source',''))" 2>/dev/null)

# Get agent ID from tmux pane attribute
AGENT_ID=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null)

if [ -z "$AGENT_ID" ]; then
    echo "[hook] WARNING: Could not identify agent role from tmux @agent_id."
    echo "[hook] Run manually: tmux display-message -t \"\$TMUX_PANE\" -p '#{@agent_id}'"
    exit 0
fi

# Ashigaru: skip instructions on /clear recovery (cost saving)
if [[ "$AGENT_ID" == ashigaru* && "$SOURCE" == "clear" ]]; then
    echo "[hook] Agent $AGENT_ID: /clear recovery — skipping instructions (cost saving)"
    exit 0
fi

# Map agent_id to instructions file
case "$AGENT_ID" in
    shogun)
        INSTRUCTIONS_FILE="$PROJECT_DIR/instructions/shogun.md"
        ;;
    daishogun)
        INSTRUCTIONS_FILE="$PROJECT_DIR/instructions/daishogun.md"
        ;;
    karo)
        INSTRUCTIONS_FILE="$PROJECT_DIR/instructions/karo.md"
        ;;
    ashigaru*)
        INSTRUCTIONS_FILE="$PROJECT_DIR/instructions/ashigaru.md"
        ;;
    gunshi)
        INSTRUCTIONS_FILE="$PROJECT_DIR/instructions/gunshi.md"
        ;;
    *)
        echo "[hook] WARNING: Unknown agent_id: $AGENT_ID"
        exit 0
        ;;
esac

if [ -f "$INSTRUCTIONS_FILE" ]; then
    echo "[hook] Agent identified: $AGENT_ID (source: ${SOURCE:-unknown})"
    echo "[hook] Loading instructions from: $INSTRUCTIONS_FILE"
    echo "---"
    # Show forbidden actions prominently
    PYTHON_BIN="/Users/mino/chrono/claude/multi-agent-shogun/.venv/bin/python3"
    [ -x "$PYTHON_BIN" ] || PYTHON_BIN="python3"
    "$PYTHON_BIN" - "$INSTRUCTIONS_FILE" <<'PYEOF'
import sys, re

filepath = sys.argv[1]
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Extract YAML front matter (between first --- and second ---)
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not match:
    sys.exit(0)

try:
    import yaml
    front_matter = yaml.safe_load(match.group(1))
except Exception:
    sys.exit(0)

forbidden = front_matter.get('forbidden_actions', [])
if not forbidden:
    sys.exit(0)

print("=====================================")
print("⛔ FORBIDDEN ACTIONS（絶対遵守）")
print("=====================================")
for f in forbidden:
    fid = f.get('id', '?')
    desc = f.get('description', f.get('action', '?'))
    parts = [f"{fid}: {desc}"]
    if 'delegate_to' in f:
        parts.append(f"→ delegate_to: {f['delegate_to']}")
    if 'use_instead' in f:
        parts.append(f"→ use_instead: {f['use_instead']}")
    if 'reason' in f:
        parts.append(f"[reason: {f['reason']}]")
    print(" ".join(parts))
print("=====================================")
PYEOF
    2>/dev/null || true
    echo ""
    cat "$INSTRUCTIONS_FILE"
else
    echo "[hook] WARNING: Instructions file not found: $INSTRUCTIONS_FILE"
fi

exit 0
