"""
Slack PR detection utilities.
Detects GitHub PR URLs and approval commands from Slack message text.
"""

import re
from typing import Optional


# GitHub PR URL pattern: https://github.com/{owner}/{repo}/pull/{number}
_PR_URL_PATTERN = re.compile(
    r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/(\d+)"
)

# Approval pattern: "approve {number}", "approve #{number}", "承認 {number}"
# NOTE: "approved" (past tense) must NOT match
_APPROVAL_PATTERN = re.compile(
    r"(?:\bapprove(?!d)\b|承認)\s+#?(\d+)",
    re.IGNORECASE,
)

# Phase 1 completion pattern: bot's own message in #shogun
# e.g. "🏯 PR #89 Phase 1分析完了"
_PHASE1_DONE_PATTERN = re.compile(
    r"PR\s+#?(\d+)\s+Phase\s*1.*(?:分析完了|analysis complete)",
    re.IGNORECASE,
)


def detect_phase1_done(text: str) -> Optional[int]:
    """
    Detect a Phase 1 completion message (posted by bot to #shogun).

    Returns the PR number (int) if matched, None otherwise.
    """
    match = _PHASE1_DONE_PATTERN.search(text)
    if not match:
        return None
    return int(match.group(1))


def detect_pr_url(text: str) -> Optional[dict]:
    """
    Detect a GitHub PR URL in the given Slack message text.

    Returns a dict with keys: pr_number (int), owner, repo, pr_url
    Returns None if no PR URL is found.
    """
    match = _PR_URL_PATTERN.search(text)
    if not match:
        return None
    owner, repo, pr_number_str = match.group(1), match.group(2), match.group(3)
    return {
        "pr_number": int(pr_number_str),
        "owner": owner,
        "repo": repo,
        "pr_url": match.group(0),
    }


def detect_approval(text: str) -> Optional[int]:
    """
    Detect an approval command in the given Slack message text.

    Returns the PR number (int) if "approve {number}" is found.
    Returns None otherwise.
    """
    match = _APPROVAL_PATTERN.search(text)
    if not match:
        return None
    return int(match.group(1))
