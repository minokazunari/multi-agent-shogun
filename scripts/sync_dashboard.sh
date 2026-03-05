#\!/bin/bash
# sync_dashboard.sh - Linux side: commit and push dashboard/reports changes for Mac daishogun to pull
set -e

REPO_DIR="${REPO_DIR:-/home/mino/chrono/repos/multi-agent-shogun}"

cd "$REPO_DIR"

CHANGED=0

# Check for uncommitted changes in tracked files
git diff --quiet dashboard.md queue/reports/ || CHANGED=1

# Check for untracked or newly staged files in target paths
git status --porcelain dashboard.md queue/reports/ | grep -q . && CHANGED=1

if [ "$CHANGED" -eq 0 ]; then
    echo "sync: no changes detected. Skipping commit."
    exit 0
fi

# Stage target files
git add dashboard.md queue/reports/*.yaml

git commit -m "sync: dashboard $(date '+%H:%M')"

# Push; on failure, report to stderr and exit 1
git push || { echo "ERROR: git push failed" >&2; exit 1; }

echo "sync: dashboard pushed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
