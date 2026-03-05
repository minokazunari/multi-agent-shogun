#!/bin/bash
set -e

# army_start.sh — Linux 6-pane startup for shogun army
# Pane layout: main-vertical (left=shogun large, right=5 panes stacked)
#   Pane 0: shogun   (opus)
#   Pane 1: karo     (opus)
#   Pane 2: gunshi   (opus)
#   Pane 3: ashigaru1 (sonnet)
#   Pane 4: ashigaru2 (sonnet)
#   Pane 5: ashigaru3 (sonnet)

WORKDIR=/home/mino/chrono/repos/multi-agent-shogun

# Kill existing session if present
tmux kill-session -t shogun 2>/dev/null || true

# Create new session (pane 0 = shogun)
tmux new-session -d -s shogun -x 220 -y 55

# Rename window to "main" (required by watcher_supervisor.sh: "shogun:main.0")
tmux rename-window -t shogun:0 main

# Create 5 more panes (split with tiled re-balance to avoid "no space" error)
for i in 1 2 3 4 5; do
    tmux split-window -t shogun:main
    tmux select-layout -t shogun:main tiled
done

# Apply main-vertical layout: pane 0 on left (large), panes 1-5 on right (stacked)
tmux select-layout -t shogun:main main-vertical

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
