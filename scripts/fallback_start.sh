#!/bin/bash
set -e

# fallback_start.sh — Mac-only fallback: all 6 agents on Mac when Linux is down
# Disables cross-machine routing via INBOX_LOCAL_ONLY=1
#
# Session 1: daishogun
#   Pane 0: daishogun (opus)
#
# Session 2: multiagent
#   Pane 0: karo      (opus)
#   Pane 1: gunshi    (opus)
#   Pane 2: ashigaru1 (sonnet)
#   Pane 3: ashigaru2 (sonnet)
#   Pane 4: ashigaru3 (sonnet)

WORKDIR=/Users/mino/chrono/claude/multi-agent-shogun

# Kill existing sessions if present
tmux kill-session -t daishogun 2>/dev/null || true
tmux kill-session -t multiagent 2>/dev/null || true

# ---- Session 1: daishogun (1 pane) ----
tmux new-session -d -s daishogun -x 220 -y 55

tmux set-option -p -t daishogun:0.0 @agent_id daishogun
tmux set-option -p -t daishogun:0.0 @agent_cli claude

tmux send-keys -t daishogun:0.0 "cd $WORKDIR" Enter
tmux send-keys -t daishogun:0.0 "export INBOX_LOCAL_ONLY=1" Enter
tmux send-keys -t daishogun:0.0 "claude --dangerously-skip-permissions --model opus" Enter

# ---- Session 2: multiagent (5 panes, window name "agents") ----
tmux new-session -d -s multiagent -x 220 -y 55

# Rename initial window to "agents" (required by watcher_supervisor.sh: "multiagent:agents.N")
tmux rename-window -t multiagent:0 agents

# Create 4 more panes
tmux split-window -t multiagent:agents.0 -v
tmux split-window -t multiagent:agents.1 -v
tmux split-window -t multiagent:agents.2 -v
tmux split-window -t multiagent:agents.3 -v

# Apply tiled layout for 5 equal panes
tmux select-layout -t multiagent:agents tiled

# Set agent IDs
tmux set-option -p -t multiagent:agents.0 @agent_id karo
tmux set-option -p -t multiagent:agents.1 @agent_id gunshi
tmux set-option -p -t multiagent:agents.2 @agent_id ashigaru1
tmux set-option -p -t multiagent:agents.3 @agent_id ashigaru2
tmux set-option -p -t multiagent:agents.4 @agent_id ashigaru3

# Set agent CLI
for i in 0 1 2 3 4; do
    tmux set-option -p -t "multiagent:agents.$i" @agent_cli claude
done

# cd to WORKDIR and set INBOX_LOCAL_ONLY in all multiagent panes
for i in 0 1 2 3 4; do
    tmux send-keys -t "multiagent:agents.$i" "cd $WORKDIR" Enter
    tmux send-keys -t "multiagent:agents.$i" "export INBOX_LOCAL_ONLY=1" Enter
done

# Launch Claude in multiagent session
tmux send-keys -t multiagent:agents.0 "claude --dangerously-skip-permissions --model opus" Enter
tmux send-keys -t multiagent:agents.1 "claude --dangerously-skip-permissions --model opus" Enter
tmux send-keys -t multiagent:agents.2 "claude --dangerously-skip-permissions --model sonnet" Enter
tmux send-keys -t multiagent:agents.3 "claude --dangerously-skip-permissions --model sonnet" Enter
tmux send-keys -t multiagent:agents.4 "claude --dangerously-skip-permissions --model sonnet" Enter

# Auto-respond to effort prompts in all panes
sleep 8
tmux send-keys -t daishogun:0.0 "" Enter
for i in 0 1 2 3 4; do
    tmux send-keys -t "multiagent:agents.$i" "" Enter
done

# Start watcher_supervisor in background
bash $WORKDIR/scripts/watcher_supervisor.sh &

echo "Fallback mode started. Mac-only (INBOX_LOCAL_ONLY=1)"
echo "  daishogun:0.0          = daishogun (opus)"
echo "  multiagent:agents.0    = karo      (opus)"
echo "  multiagent:agents.1    = gunshi    (opus)"
echo "  multiagent:agents.2    = ashigaru1 (sonnet)"
echo "  multiagent:agents.3    = ashigaru2 (sonnet)"
echo "  multiagent:agents.4    = ashigaru3 (sonnet)"
