#!/bin/bash
set -e

# army_start.sh — Linux 6-pane startup for shogun army
# Pane layout: 2-column (left 50% = shogun+karo, right 50% = gunshi+ashigaru1-3)
#   Left column:  pane 0 (shogun), pane 1 (karo)
#   Right column: pane 2 (gunshi), pane 3 (ashigaru1), pane 4 (ashigaru2), pane 5 (ashigaru3)

WORKDIR=/home/mino/chrono/repos/multi-agent-shogun

# Kill existing session if present
tmux kill-session -t shogun 2>/dev/null || true

# Create new session (pane 0 = shogun)
tmux new-session -d -s shogun -x 220 -y 55

# Rename window to "main" (required by watcher_supervisor.sh: "shogun:main.0")
tmux rename-window -t shogun:0 main

# Build 2-column layout: left 50% (2 panes), right 50% (4 panes)
# Start: pane 0 = full window

# Split horizontally: left (pane 0) | right (pane 1) — 50/50
tmux split-window -h -t shogun:main.0 -l 50%

# Split left column vertically: pane 0 (shogun) / pane 1 (karo)
tmux split-window -v -t shogun:main.0 -l 50%

# Split right column vertically into 4 panes
# After left split, right pane is now pane 2
tmux split-window -v -t shogun:main.2 -l 75%
tmux split-window -v -t shogun:main.3 -l 67%
tmux split-window -v -t shogun:main.4 -l 50%

# Set agent IDs
tmux set-option -p -t shogun:main.0 @agent_id shogun
tmux set-option -p -t shogun:main.1 @agent_id karo
tmux set-option -p -t shogun:main.2 @agent_id gunshi
tmux set-option -p -t shogun:main.3 @agent_id ashigaru1
tmux set-option -p -t shogun:main.4 @agent_id ashigaru2
tmux set-option -p -t shogun:main.5 @agent_id ashigaru3

# Set agent CLI
for i in 0 1 2 3 4 5; do
    tmux set-option -p -t "shogun:main.$i" @agent_cli claude
done

# cd to WORKDIR in all panes
for i in 0 1 2 3 4 5; do
    tmux send-keys -t "shogun:main.$i" "cd $WORKDIR" Enter
done

# Launch Claude in each pane
tmux send-keys -t shogun:main.0 "claude --dangerously-skip-permissions --model opus" Enter
tmux send-keys -t shogun:main.1 "claude --dangerously-skip-permissions --model opus" Enter
tmux send-keys -t shogun:main.2 "claude --dangerously-skip-permissions --model opus" Enter
tmux send-keys -t shogun:main.3 "claude --dangerously-skip-permissions --model sonnet" Enter
tmux send-keys -t shogun:main.4 "claude --dangerously-skip-permissions --model sonnet" Enter
tmux send-keys -t shogun:main.5 "claude --dangerously-skip-permissions --model sonnet" Enter

# Auto-respond to effort prompt
sleep 8
for i in 0 1 2 3 4 5; do
    tmux send-keys -t "shogun:main.$i" "" Enter
done

# Start watcher_supervisor in background
bash $WORKDIR/scripts/watcher_supervisor.sh &

# Create symlink for convenience
mkdir -p ~/bin
ln -sf $WORKDIR/scripts/army_start.sh ~/bin/shutsujin

echo "Army started successfully. Session: shogun (6 panes)"
echo "  shogun:main.0 = shogun   (opus)"
echo "  shogun:main.1 = karo     (opus)"
echo "  shogun:main.2 = gunshi   (opus)"
echo "  shogun:main.3 = ashigaru1 (sonnet)"
echo "  shogun:main.4 = ashigaru2 (sonnet)"
echo "  shogun:main.5 = ashigaru3 (sonnet)"
