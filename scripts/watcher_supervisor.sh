#!/usr/bin/env bash
set -euo pipefail

# Keep inbox watchers alive in a persistent tmux-hosted shell.
# This script is designed to run forever.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

mkdir -p logs queue/inbox

ensure_inbox_file() {
    local agent="$1"
    if [ ! -f "queue/inbox/${agent}.yaml" ]; then
        printf 'messages: []\n' > "queue/inbox/${agent}.yaml"
    fi
}

pane_exists() {
    local pane="$1"
    tmux list-panes -a -F "#{session_name}:#{window_name}.#{pane_index}" 2>/dev/null | grep -qx "$pane"
}

start_watcher_if_missing() {
    local agent="$1"
    local pane="$2"
    local log_file="$3"
    local cli

    ensure_inbox_file "$agent"
    if ! pane_exists "$pane"; then
        return 0
    fi

    if pgrep -f "scripts/inbox_watcher.sh ${agent} " >/dev/null 2>&1; then
        return 0
    fi

    cli=$(tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || echo "codex")
    nohup bash scripts/inbox_watcher.sh "$agent" "$pane" "$cli" >> "$log_file" 2>&1 &
}

OS="$(uname -s)"

while true; do
    if [ "$OS" = "Darwin" ]; then
        # Mac版: 大将軍のみ監視
        start_watcher_if_missing "daishogun" "daishogun:0.0" "logs/inbox_watcher_daishogun.log"
    else
        # Linux版: 将軍/家老/軍師/足軽を監視
        start_watcher_if_missing "shogun"    "shogun:0.0" "logs/inbox_watcher_shogun.log"
        start_watcher_if_missing "karo"      "shogun:0.1" "logs/inbox_watcher_karo.log"
        start_watcher_if_missing "gunshi"    "shogun:0.2" "logs/inbox_watcher_gunshi.log"
        start_watcher_if_missing "ashigaru1" "shogun:0.3" "logs/inbox_watcher_ashigaru1.log"
        start_watcher_if_missing "ashigaru2" "shogun:0.4" "logs/inbox_watcher_ashigaru2.log"
        start_watcher_if_missing "ashigaru3" "shogun:0.5" "logs/inbox_watcher_ashigaru3.log"
    fi
    sleep 5
done
