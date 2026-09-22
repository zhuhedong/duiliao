from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.api.v1.ai import AIAnalyzeRequest
from app.services.db_service import test_pg_connection as probe_pg_connection
from app.services.settings_service import validate_external_url


def test_provider_url_rejects_private_and_non_http_targets() -> None:
    with pytest.raises(ValueError, match="内网"):
        validate_external_url("http://127.0.0.1:8080/v1", resolve_dns=False)

    with pytest.raises(ValueError, match="http 或 https"):
        validate_external_url("file:///etc/passwd", resolve_dns=False)


def test_provider_url_preserves_public_custom_gateway_path() -> None:
    assert (
        validate_external_url("HTTPS://api.example.test/v1/", resolve_dns=False)
        == "https://api.example.test/v1"
    )


def test_ai_request_rejects_oversized_custom_data() -> None:
    with pytest.raises(ValidationError, match="不能超过 1 MB"):
        AIAnalyzeRequest(custom_data={"payload": "x" * 1_100_000}, fetch_fresh=False)


def test_pg_probe_rejects_private_target_before_connecting() -> None:
    result = probe_pg_connection("postgresql://user:pass@127.0.0.1:5432/app")
    assert result["ok"] is False
    assert "内网" in result["error"]
