"""Unit tests for System Settings service and AI configuration storage."""
import unittest
from unittest.mock import MagicMock, patch

from app.db.session import SessionLocal, init_db
from app.services.ai.client import get_ai_client
from app.services.settings_service import (
    get_all_ai_settings,
    is_masked_key,
    mask_api_key,
    save_ai_settings,
    test_ai_connection as run_ai_connection_test,
)


class TestSettingsService(unittest.TestCase):
    def setUp(self):
        init_db()
        self.db = SessionLocal()
        self.dns_patcher = patch(
            "socket.getaddrinfo",
            return_value=[(2, 1, 6, "", ("104.26.0.1", 443))],
        )
        self.dns_patcher.start()

    def tearDown(self):
        self.dns_patcher.stop()
        self.db.close()

    def test_mask_api_key(self):
        self.assertEqual(mask_api_key(""), "")
        self.assertEqual(mask_api_key("12345"), "••••••••")
        self.assertEqual(mask_api_key("sk-1234567890abcdef"), "sk-••••••••cdef")
        self.assertTrue(is_masked_key("sk-••••••••cdef"))
        self.assertFalse(is_masked_key("sk-1234567890abcdef"))

    def test_get_and_save_ai_settings(self):
        # 1. Save new AI settings
        payload = {
            "default_provider": "openai",
            "openai": {
                "base_url": "https://api.deepseek.com/v1",
                "api_key": "sk-deepseek-test-key-12345",
                "model": "deepseek-chat",
            },
            "gemini": {
                "base_url": "https://generativelanguage.googleapis.com",
                "api_key": "AIzaSyTestKeyGemini123456",
                "model": "gemini-2.5-flash",
            },
        }

        saved = save_ai_settings(self.db, payload)
        self.assertEqual(saved["default_provider"], "openai")
        self.assertEqual(saved["openai"]["base_url"], "https://api.deepseek.com/v1")
        self.assertTrue(saved["openai"]["is_configured"])
        # API key should be masked in returned response
        self.assertTrue("••••" in saved["openai"]["api_key"])

        # 2. Re-saving with masked key should NOT overwrite the real key
        masked_update = {
            "openai": {
                "api_key": saved["openai"]["api_key"],  # masked
                "model": "deepseek-reasoner",
            }
        }
        saved2 = save_ai_settings(self.db, masked_update)
        self.assertEqual(saved2["openai"]["model"], "deepseek-reasoner")

        # 3. Verify real unmasked key is preserved in DB
        unmasked = get_all_ai_settings(self.db, mask=False)
        self.assertEqual(unmasked["openai"]["api_key"], "sk-deepseek-test-key-12345")

    def test_get_ai_client_uses_db_settings(self):
        save_ai_settings(
            self.db,
            {
                "openai": {
                    "base_url": "https://api.test-db-endpoint.com/v1",
                    "api_key": "sk-test-db-key-9999",
                    "model": "test-db-model",
                }
            },
        )

        client = get_ai_client(provider="openai")
        self.assertEqual(client.base_url, "https://api.test-db-endpoint.com/v1")
        self.assertEqual(client.api_key, "sk-test-db-key-9999")
        self.assertEqual(client.default_model, "test-db-model")

    def test_test_ai_connection_empty_key(self):
        res = run_ai_connection_test(provider="openai", api_key="")
        self.assertFalse(res["ok"])
        self.assertIn("为空", res["message"])

    @patch("httpx.Client.post")
    def test_test_ai_connection_success(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.raise_for_status.return_value = None
        mock_post.return_value = mock_resp

        res = run_ai_connection_test(
            provider="openai",
            base_url="https://api.deepseek.com/v1",
            api_key="sk-real-test-key-12345",
            model="deepseek-chat",
        )
        self.assertTrue(res["ok"])
        self.assertIn("连接成功", res["message"])


if __name__ == "__main__":
    unittest.main()
