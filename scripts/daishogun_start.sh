#!/bin/bash
set -e

# daishogun_start.sh — Mac大将軍 1-pane startup
# Starts daishogun locally on Mac, then launches Linux army via SSH.
#
# Pane layout:
#   daishogun session, pane 0: daishogun (opus)

WORKDIR=/Users/mino/chrono/claude/multi-agent-shogun

# Kill existing session if present
tmux kill-session -t daishogun 2>/dev/null || true

# Create new session (1 pane = daishogun)
tmux new-session -d -s daishogun -x 220 -y 55

# Set agent properties
tmux set-option -p -t daishogun:0.0 @agent_id daishogun
tmux set-option -p -t daishogun:0.0 @agent_cli claude

# cd to WORKDIR and launch Claude (opus)
tmux send-keys -t daishogun:0.0 "cd $WORKDIR" Enter
tmux send-keys -t daishogun:0.0 "claude --dangerously-skip-permissions --model opus" Enter

# Auto-respond to effort prompt
sleep 8
tmux send-keys -t daishogun:0.0 "" Enter

# Launch Linux army via SSH (non-blocking, error tolerant)
ssh mino@192.168.0.194 \
    "nohup bash ~/chrono/repos/multi-agent-shogun/scripts/army_start.sh > /tmp/army_start.log 2>&1 &" \
    || echo "WARNING: Linux army_start.sh failed. Mac-only mode."

# Wait for Linux army to initialize, then create window 1 (shogun monitor)
sleep 5
tmux new-window -t daishogun:1
tmux send-keys -t daishogun:1 "ssh mino@192.168.0.194 -t 'tmux attach-session -t shogun' || echo -e '\\n\\n===\\nSSH接続失敗。Linux側で以下を実行:\\n  tmux attach -t shogun\\n==='" Enter

# Start watcher_supervisor in background
bash $WORKDIR/scripts/watcher_supervisor.sh &

echo "Daishogun started. Linux army launched via SSH."
echo "  daishogun:0.0 = daishogun (opus)"
echo "  daishogun:1   = SSH → Linux shogun session"
echo "  Linux log: mino@192.168.0.194:/tmp/army_start.log"

# Switch to window 0 (daishogun pane) before attaching
tmux select-window -t daishogun:0

# Attach to daishogun session
if [ -n "${TMUX:-}" ]; then
    exec tmux switch-client -t daishogun
else
    exec tmux attach-session -t daishogun
fi
