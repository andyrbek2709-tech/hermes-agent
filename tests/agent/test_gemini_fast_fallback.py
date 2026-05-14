"""Regression tests for #13636 — CloudCode / Gemini CLI rate-limit fallback.

_pool_may_recover_from_rate_limit() is the hinge between credential-pool
rotation and fallback-provider activation.  For CloudCode (Gemini CLI /
Gemini OAuth) the 429 is an account-wide throttle, so waiting for pool
rotation is pointless — prefer fallback immediately.
"""
from unittest.mock import MagicMock

from run_agent import _pool_may_recover_from_rate_limit


def _pool(entries: int = 2):
    p = MagicMock()
    p.has_available.return_value = True
    p.entries.return_value = list(range(entries))
    return p


def test_cloudcode_provider_skips_pool_rotation():
    assert _pool_may_recover_from_rate_limit(
        _pool(entries=3),
        provider="google-gemini-cli",
        base_url="cloudcode-pa://google",
    ) is False


def test_cloudcode_base_url_skips_pool_rotation_even_on_alias_provider():
    # Even if the provider label is something else, a cloudcode-pa:// URL
    # signals the account-wide quota regime.
    assert _pool_may_recover_from_rate_limit(
        _pool(entries=3),
        provider="custom-provider",
        base_url="cloudcode-pa://google",
    ) is False


def test_non_cloudcode_multi_entry_pool_still_recovers():
    assert _pool_may_recover_from_rate_limit(
        _pool(entries=3),
        provider="openrouter",
        base_url="https://openrouter.ai/api/v1",
    ) is True


def test_single_entry_pool_skips_rotation_regardless_of_provider():
    # Pre-existing single-entry-pool exception (#11314) still holds.
    assert _pool_may_recover_from_rate_limit(
        _pool(entries=1),
        provider="openrouter",
        base_url="https://openrouter.ai/api/v1",
    ) is False


def test_exhausted_pool_skips_rotation():
    p = MagicMock()
    p.has_available.return_value = False
    assert _pool_may_recover_from_rate_limit(p) is False


def test_no_pool_skips_rotation():
    assert _pool_may_recover_from_rate_limit(None) is False


class TestGeminiFreeTierSkipsPoolRotation:
    """Free-tier Gemini quota exhaustion should bypass pool rotation."""

    def test_free_tier_error_skips_rotation_even_with_multi_entry_pool(self):
        # A multi-entry pool would normally allow rotation, but a free-tier
        # daily quota 429 won't recover — skip to fallback immediately.
        free_tier_msg = (
            "Gemini HTTP 429 (RESOURCE_EXHAUSTED): Quota exceeded for metric: "
            "generativelanguage.googleapis.com/generate_content_free_tier_input_token_count"
        )
        assert _pool_may_recover_from_rate_limit(
            _pool(entries=3),
            provider="gemini",
            base_url="https://generativelanguage.googleapis.com/v1beta",
            error_message=free_tier_msg,
        ) is False

    def test_free_tier_requests_metric_also_skips_rotation(self):
        free_tier_msg = (
            "Quota exceeded for metric: "
            "generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20"
        )
        assert _pool_may_recover_from_rate_limit(
            _pool(entries=2),
            provider="gemini",
            error_message=free_tier_msg,
        ) is False

    def test_non_free_tier_429_still_allows_pool_rotation(self):
        # A transient rate limit (not free-tier) on a multi-entry pool should
        # still go through pool rotation.
        paid_rate_limit_msg = "Gemini HTTP 429 (RESOURCE_EXHAUSTED): Rate limit exceeded"
        assert _pool_may_recover_from_rate_limit(
            _pool(entries=3),
            provider="gemini",
            base_url="https://generativelanguage.googleapis.com/v1beta",
            error_message=paid_rate_limit_msg,
        ) is True

    def test_no_error_message_falls_through_to_pool_size_check(self):
        # No error_message → existing pool-size logic applies.
        assert _pool_may_recover_from_rate_limit(
            _pool(entries=3),
            provider="gemini",
            error_message=None,
        ) is True
        assert _pool_may_recover_from_rate_limit(
            _pool(entries=1),
            provider="gemini",
            error_message=None,
        ) is False
