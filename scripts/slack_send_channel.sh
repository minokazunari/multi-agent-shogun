#!/usr/bin/env bash
# Slack message sender — posts to specified channel (optionally as thread reply)
# Usage: bash scripts/slack_send_channel.sh <channel_id> "message text" [thread_ts]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH_FILE="$SCRIPT_DIR/config/slack_auth.env"

if [ ! -f "$AUTH_FILE" ]; then
    echo "[slack_send_channel] config/slack_auth.env not found" >&2
    exit 1
fi

source "$AUTH_FILE"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: slack_send_channel.sh <channel_id> \"message\" [thread_ts]" >&2
    exit 1
fi

CHANNEL_ID="$1"
MESSAGE="$2"
THREAD_TS="${3:-}"

ESCAPED_MSG=$(python3 -c "import json; print(json.dumps('$MESSAGE'))" 2>/dev/null || echo "\"$MESSAGE\"")

if [ -n "$THREAD_TS" ]; then
    PAYLOAD="{\"channel\": \"$CHANNEL_ID\", \"text\": $ESCAPED_MSG, \"thread_ts\": \"$THREAD_TS\"}"
else
    PAYLOAD="{\"channel\": \"$CHANNEL_ID\", \"text\": $ESCAPED_MSG}"
fi

curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    > /dev/null
