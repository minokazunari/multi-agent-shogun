#!/usr/bin/env bash
# Slack message sender — posts to specified channel
# Usage: bash scripts/slack_send_channel.sh <channel_id> "message text"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH_FILE="$SCRIPT_DIR/config/slack_auth.env"

if [ ! -f "$AUTH_FILE" ]; then
    echo "[slack_send_channel] config/slack_auth.env not found" >&2
    exit 1
fi

source "$AUTH_FILE"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: slack_send_channel.sh <channel_id> \"message\"" >&2
    exit 1
fi

CHANNEL_ID="$1"
MESSAGE="$2"

curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"channel\": \"$CHANNEL_ID\", \"text\": $(python3 -c "import json; print(json.dumps('$MESSAGE'))" 2>/dev/null || echo "\"$MESSAGE\"")}" \
    > /dev/null
