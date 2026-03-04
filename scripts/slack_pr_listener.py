"""
Slack Socket Mode PR Review Listener for Shogun System.

Listens for GitHub PR URLs in project channels → triggers Phase 1 analysis.
Listens for approval commands in #shogun → triggers Phase 2 posting.

Environment variables:
    SLACK_BOT_TOKEN    - Bot OAuth token (xoxb-...)
    SLACK_APP_TOKEN    - App-level token for Socket Mode (xapp-...)
    SHOGUN_CHANNEL_ID  - Channel ID of #shogun
    SCRIPT_DIR         - Absolute path to the multi-agent-shogun root directory
"""

import datetime
import fcntl
import os
import subprocess
import sys
import tempfile

import yaml
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

from slack_pr_detector import detect_approval, detect_phase1_done, detect_pr_url

# ── Environment ──────────────────────────────────────────────────────────────
SCRIPT_DIR = os.environ["SCRIPT_DIR"]
SHOGUN_CHANNEL_ID = os.environ.get("SHOGUN_CHANNEL_ID", "")
BOT_TOKEN = os.environ["SLACK_BOT_TOKEN"]
APP_TOKEN = os.environ["SLACK_APP_TOKEN"]

PR_REVIEWS_PATH = os.path.join(SCRIPT_DIR, "queue", "pr_reviews.yaml")
PR_TASKS_DIR = os.path.join(SCRIPT_DIR, "queue", "joushu", "pr_tasks")

app = App(token=BOT_TOKEN)

# Cache bot user ID to skip own messages
_bot_user_id = None


def get_bot_user_id() -> str:
    global _bot_user_id
    if _bot_user_id is None:
        resp = app.client.auth_test()
        _bot_user_id = resp["user_id"]
    return _bot_user_id


# ── State management (pr_reviews.yaml with flock) ────────────────────────────

def load_reviews() -> list:
    """Load pr_reviews.yaml and return the reviews list."""
    if not os.path.exists(PR_REVIEWS_PATH):
        return []
    try:
        with open(PR_REVIEWS_PATH, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        reviews = data.get("reviews", [])
        return reviews if isinstance(reviews, list) else []
    except Exception as e:
        print(f"[slack_pr_listener] load_reviews error: {e}", file=sys.stderr)
        return []


def save_reviews(reviews: list) -> None:
    """Atomically save reviews list to pr_reviews.yaml using flock."""
    os.makedirs(os.path.dirname(PR_REVIEWS_PATH), exist_ok=True)
    lock_path = PR_REVIEWS_PATH + ".lock"
    with open(lock_path, "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            tmp_fd, tmp_path = tempfile.mkstemp(
                dir=os.path.dirname(PR_REVIEWS_PATH), suffix=".tmp"
            )
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                yaml.safe_dump(
                    {"reviews": reviews},
                    f,
                    default_flow_style=False,
                    allow_unicode=True,
                    sort_keys=False,
                )
            os.replace(tmp_path, PR_REVIEWS_PATH)
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)


# ── PR task YAML creation ─────────────────────────────────────────────────────

def create_pr_task(pr_info: dict, phase: int = 1) -> str:
    """
    Write a Phase 1 or Phase 2 task YAML to queue/joushu/pr_tasks/pr_{number}.yaml.
    Returns the task file path.
    """
    os.makedirs(PR_TASKS_DIR, exist_ok=True)
    pr_number = pr_info["pr_number"]
    task_path = os.path.join(PR_TASKS_DIR, f"pr_{pr_number}.yaml")

    task = {
        "task": {
            "type": f"pr_review_phase{phase}",
            "pr_number": pr_number,
            "owner": pr_info["owner"],
            "repo": pr_info["repo"],
            "pr_url": pr_info["pr_url"],
            "slack_channel": pr_info.get("slack_channel", ""),
            "message_ts": pr_info.get("message_ts", ""),
            "timestamp": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        }
    }
    with open(task_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(
            task,
            f,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        )
    return task_path


def send_slack_channel(channel_id: str, message: str, thread_ts: str = "") -> None:
    """Post a message to the specified Slack channel via slack_send_channel.sh.
    If thread_ts is provided, posts as a thread reply.
    """
    cmd = ["bash", os.path.join(SCRIPT_DIR, "scripts", "slack_send_channel.sh"), channel_id, message]
    if thread_ts:
        cmd.append(thread_ts)
    subprocess.run(cmd, capture_output=True)


def write_inbox(target: str, content: str, msg_type: str, sender: str) -> None:
    """Write a message to an agent's inbox via inbox_write.sh."""
    subprocess.run(
        [
            "bash",
            os.path.join(SCRIPT_DIR, "scripts", "inbox_write.sh"),
            target,
            content,
            msg_type,
            sender,
        ],
        capture_output=True,
    )


# ── Handlers ─────────────────────────────────────────────────────────────────

def handle_pr_detection(text: str, channel_id: str, message_ts: str = "") -> None:
    """
    Detect a PR URL in a non-#shogun channel message.
    If detected and not already being processed, kick off Phase 1.
    """
    pr_info = detect_pr_url(text)
    if not pr_info:
        return

    pr_number = pr_info["pr_number"]
    pr_info["slack_channel"] = channel_id

    # Duplicate check: ignore if already in progress
    reviews = load_reviews()
    for r in reviews:
        if r.get("pr_number") == pr_number and r.get("status") not in ("posted", "rejected"):
            print(
                f"[slack_pr_listener] PR #{pr_number} already in progress (status={r.get('status')}), skipping.",
                file=sys.stderr,
            )
            return

    print(f"[slack_pr_listener] PR #{pr_number} detected in channel {channel_id}", file=sys.stderr)

    # Notify source channel (thread reply to the original message)
    send_slack_channel(channel_id, f"🔍 PR #{pr_number} detected. Starting review...", message_ts)

    # Add entry to pr_reviews.yaml
    reviews.append({
        "pr_number": pr_number,
        "owner": pr_info["owner"],
        "repo": pr_info["repo"],
        "pr_url": pr_info["pr_url"],
        "slack_channel": channel_id,
        "message_ts": message_ts,
        "status": "phase1_running",
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
    })
    save_reviews(reviews)

    # Write Phase 1 task YAML (include message_ts for thread replies)
    pr_info["message_ts"] = message_ts
    task_path = create_pr_task(pr_info, phase=1)

    # Notify joushu (城主) via inbox
    write_inbox(
        "joushu",
        f"PR #{pr_number} detected in Slack. Task YAML: {task_path}",
        "pr_review_request",
        "slack_pr_listener",
    )


def handle_approval(text: str) -> None:
    """
    Detect an approval command in #shogun ("approve {number}").
    If matching phase1_done entry found, advance to approved and trigger Phase 2.
    """
    pr_number = detect_approval(text)
    if pr_number is None:
        return

    reviews = load_reviews()
    target = None
    for r in reviews:
        if r.get("pr_number") == pr_number and r.get("status") in ("phase1_done", "phase1_running"):
            target = r
            break

    if not target:
        print(
            f"[slack_pr_listener] approve #{pr_number}: no reviewable entry found, ignoring.",
            file=sys.stderr,
        )
        return

    print(f"[slack_pr_listener] PR #{pr_number} approved — triggering Phase 2", file=sys.stderr)

    # Update status
    target["status"] = "approved"
    save_reviews(reviews)

    # Write Phase 2 task YAML (overwrite same file, include message_ts for thread reply)
    pr_info = {
        "pr_number": target["pr_number"],
        "owner": target["owner"],
        "repo": target["repo"],
        "pr_url": target["pr_url"],
        "slack_channel": target.get("slack_channel", ""),
        "message_ts": target.get("message_ts", ""),
    }
    task_path = create_pr_task(pr_info, phase=2)

    # Notify joushu to execute Phase 2
    write_inbox(
        "joushu",
        f"PR #{pr_number} approved by 殿. Execute Phase 2. Task YAML: {task_path}",
        "pr_review_approved",
        "slack_pr_listener",
    )


def handle_phase1_done_detection(text: str) -> None:
    """
    Detect bot's own Phase 1 analysis message in #shogun.
    Auto-transition pr_reviews.yaml status from phase1_running to phase1_done.
    """
    pr_number = detect_phase1_done(text)
    if pr_number is None:
        return

    reviews = load_reviews()
    for r in reviews:
        if r.get("pr_number") == pr_number and r.get("status") == "phase1_running":
            r["status"] = "phase1_done"
            save_reviews(reviews)
            print(
                f"[slack_pr_listener] PR #{pr_number} Phase 1 done — status updated to phase1_done",
                file=sys.stderr,
            )
            return


@app.event("message")
def handle_message(event, say):
    user = event.get("user", "")
    text = event.get("text", "")
    if not text:
        return

    # Skip message subtypes (edits, joins, etc.)
    if event.get("subtype"):
        return

    channel_id = event.get("channel", "")
    print(
        f"[{datetime.datetime.now()}] channel={channel_id} user={user}: {text}",
        file=sys.stderr,
    )

    # Bot's own messages: only check for Phase 1 completion in #shogun
    if user == get_bot_user_id():
        if SHOGUN_CHANNEL_ID and channel_id == SHOGUN_CHANNEL_ID:
            handle_phase1_done_detection(text)
        return

    message_ts = event.get("ts", "")

    if SHOGUN_CHANNEL_ID and channel_id == SHOGUN_CHANNEL_ID:
        # #shogun: listen for approval commands
        handle_approval(text)
    else:
        # Other channels: listen for PR URLs (pass ts for thread replies)
        handle_pr_detection(text, channel_id, message_ts)


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    print(
        f"[{datetime.datetime.now()}] slack_pr_listener started (Socket Mode). "
        f"SHOGUN_CHANNEL_ID={SHOGUN_CHANNEL_ID!r}",
        file=sys.stderr,
    )
    os.makedirs(PR_TASKS_DIR, exist_ok=True)
    handler = SocketModeHandler(app, APP_TOKEN)
    handler.start()


if __name__ == "__main__":
    main()
