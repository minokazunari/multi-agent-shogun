"""
Tests for scripts/slack_pr_detector.py
"""

import sys
import os
import pytest

# Add scripts/ to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from slack_pr_detector import detect_pr_url, detect_approval, detect_phase1_done


# ===========================================================================
# detect_pr_url tests
# ===========================================================================

class TestDetectPrUrl:
    """Tests for detect_pr_url()"""

    # --- Normal cases ---

    def test_normal_url(self):
        text = "Please review https://github.com/myorg/myrepo/pull/42"
        result = detect_pr_url(text)
        assert result is not None
        assert result["owner"] == "myorg"
        assert result["repo"] == "myrepo"
        assert result["pr_number"] == 42
        assert result["pr_url"] == "https://github.com/myorg/myrepo/pull/42"

    def test_url_with_surrounding_text(self):
        text = "見てください https://github.com/chrono/darwin/pull/1399 よろしく"
        result = detect_pr_url(text)
        assert result is not None
        assert result["owner"] == "chrono"
        assert result["repo"] == "darwin"
        assert result["pr_number"] == 1399

    def test_url_without_trailing_slash(self):
        text = "https://github.com/org/repo/pull/7"
        result = detect_pr_url(text)
        assert result is not None
        assert result["pr_number"] == 7

    # --- Error cases ---

    def test_no_pr_url(self):
        text = "This is a normal message without any URL."
        assert detect_pr_url(text) is None

    def test_issue_url_not_matched(self):
        # /issues/ should not match (only /pull/ is valid)
        text = "See https://github.com/org/repo/issues/10 for details"
        assert detect_pr_url(text) is None

    def test_empty_string(self):
        assert detect_pr_url("") is None

    def test_none_input(self):
        with pytest.raises((TypeError, AttributeError)):
            detect_pr_url(None)

    # --- Edge cases ---

    def test_multiple_urls_returns_first(self):
        text = (
            "First: https://github.com/org/repo/pull/1 "
            "Second: https://github.com/org/repo/pull/2"
        )
        result = detect_pr_url(text)
        assert result is not None
        assert result["pr_number"] == 1

    def test_url_with_query_params(self):
        # Query params after the pull URL — regex matches only up to the number
        text = "https://github.com/org/repo/pull/99?diff=split"
        result = detect_pr_url(text)
        assert result is not None
        assert result["pr_number"] == 99


# ===========================================================================
# detect_approval tests
# ===========================================================================

class TestDetectApproval:
    """Tests for detect_approval()"""

    # --- Normal cases ---

    def test_approve_lowercase(self):
        assert detect_approval("approve 89") == 89

    def test_approve_uppercase(self):
        assert detect_approval("APPROVE 89") == 89

    def test_japanese_approval(self):
        assert detect_approval("承認 89") == 89

    def test_approve_with_hash(self):
        assert detect_approval("approve #89") == 89

    # --- Error cases ---

    def test_approved_past_tense_not_matched(self):
        # "approved" (past tense) must NOT trigger
        assert detect_approval("approved 89") is None

    def test_reversed_order_not_matched(self):
        # "89 approve" should not match
        assert detect_approval("89 approve") is None

    def test_empty_string(self):
        assert detect_approval("") is None

    # --- Edge cases ---

    def test_approve_with_surrounding_text(self):
        # Embedded in a sentence
        assert detect_approval("ok approve 89 please") == 89

    def test_approve_with_hash_and_surrounding_text(self):
        assert detect_approval("LGTM、approve #123 してください") == 123

    def test_japanese_approval_with_surrounding_text(self):
        assert detect_approval("この対応で承認 42 お願いします") == 42


# ===========================================================================
# detect_phase1_done tests
# ===========================================================================

class TestDetectPhase1Done:
    """Tests for detect_phase1_done()"""

    def test_japanese_format(self):
        text = "🏯 PR #89 Phase 1分析完了 (minokazunari/api_edu)"
        assert detect_phase1_done(text) == 89

    def test_english_format(self):
        text = "PR #42 Phase 1 analysis complete"
        assert detect_phase1_done(text) == 42

    def test_no_hash(self):
        text = "PR 89 Phase1分析完了"
        assert detect_phase1_done(text) == 89

    def test_no_match(self):
        assert detect_phase1_done("Regular message") is None

    def test_empty(self):
        assert detect_phase1_done("") is None
