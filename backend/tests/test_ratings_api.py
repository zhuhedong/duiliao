"""Regression tests for collector ratings query validation."""
from __future__ import annotations

import pytest
from tests.crypto_client import ApiError


def test_ratings_accepts_trimmed_positive_windows(user_client):
    response = user_client.get(
        "/collector/ratings",
        params={"lottery": "macau", "play_type": "pingte_xiao", "windows": " 30, 50,30 "},
    )
    assert response["ok"] is True
    assert response["windows"] == [30, 50]


@pytest.mark.parametrize("windows", ["0,30", "-1,30", "abc,30", "   "])
def test_ratings_rejects_invalid_windows(user_client, windows):
    with pytest.raises(ApiError) as exc:
        user_client.get(
            "/collector/ratings",
            params={"lottery": "macau", "play_type": "pingte_xiao", "windows": windows},
        )
    assert exc.value.status_code == 400
