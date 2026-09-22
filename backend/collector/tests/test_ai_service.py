"""Tests for multi-model AI adapters, prompts, context formatter, and analyzer."""
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add backend and collector to sys.path
BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"

if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))
if str(COLLECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_DIR))

from app.services.ai.analyzer import analyze_scraped_data, analyze_scraped_data_stream
from app.services.ai.client import (
    AnthropicProvider,
    GeminiProvider,
    OpenAIProvider,
    get_ai_client,
)
from app.services.ai.formatter import clean_html_to_text, format_scraped_data_for_ai
from app.services.ai.prompts import (
    get_prompt_template,
    list_prompt_templates,
)


class TestAIService(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from app.db.session import init_db
        init_db()

    def test_clean_html_to_text(self):
        html_input = """
        <div class="card">
            <h3>第259期 预测</h3>
            <p>特码推荐：<br/><b>18</b>、<b>29</b></p>
            <script>console.log("ad");</script>
            <!-- comment -->
            <table><tr><td>生肖</td><td>马, 羊</td></tr></table>
        </div>
        """
        text = clean_html_to_text(html_input)
        self.assertIn("第259期 预测", text)
        self.assertIn("特码推荐：", text)
        self.assertIn("18", text)
        self.assertIn("马, 羊", text)
        self.assertNotIn("console.log", text)
        self.assertNotIn("<div", text)

    def test_format_scraped_data_for_ai(self):
        sample_data = {
            "site_title": "测试顶尖大师",
            "modules": [
                {"id": 1, "name": "核心代码", "type": "code", "content": "<div>核心分析代码</div>"},
                {"id": 2, "name": "广告位", "type": "publicCode", "content": "<div>澳门新葡京广告</div>"},
                {"id": 3, "name": "全局样式", "type": "style", "content": "body { background: #fff; }"},
                {
                    "id": 4,
                    "name": "云顶心水",
                    "type": "content",
                    "content": "<p>第260期 特肖：龙、猴 特码：08, 20</p>",
                },
            ],
        }
        formatted = format_scraped_data_for_ai(sample_data, mode="modules_summary")
        self.assertIn("云顶心水", formatted)
        self.assertIn("第260期 特肖：龙、猴", formatted)
        self.assertNotIn("澳门新葡京广告", formatted)
        self.assertNotIn("body { background", formatted)

    def test_prompt_templates(self):
        prompts = list_prompt_templates()
        self.assertGreaterEqual(len(prompts), 5)
        template = get_prompt_template("consensus_synthesis")
        self.assertEqual(template.id, "consensus_synthesis")

        messages = template.render(context_data="测试对料数据", period="262")
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0]["role"], "system")
        self.assertEqual(messages[1]["role"], "user")
        self.assertIn("测试对料数据", messages[1]["content"])
        self.assertIn("262", messages[1]["content"])

    def test_macau_analyst_expert_prompt(self):
        template = get_prompt_template("macau_analyst_expert")
        self.assertEqual(template.id, "macau_analyst_expert")

        messages = template.render(context_data="第262期实码: 08, 19, 32", period="262")
        user_content = messages[1]["content"]

        # Verify the user requested prompt text and filtering requirements
        self.assertIn("你现在是专业的澳门六合彩分析师", user_content)
        self.assertIn("只分析帖文里的实码和生肖", user_content)
        self.assertIn("严格过滤所有“發”“猫”“？”“0O”", user_content)
        self.assertIn("给出262期热度最高的5个生肖以及重点6个号码10个号码", user_content)
        self.assertIn("第 262 期", user_content)


    @patch("httpx.Client.post")
    def test_openai_provider(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "choices": [{"message": {"content": "这是 OpenAI / DeepSeek 的对料分析结果"}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150},
        }
        mock_post.return_value = mock_resp

        provider = OpenAIProvider(
            api_key="test-key",
            base_url="https://api.deepseek.com/v1",
            default_model="deepseek-chat",
        )
        resp = provider.generate([{"role": "user", "content": "你好"}])

        self.assertEqual(resp.provider, "openai")
        self.assertEqual(resp.model, "deepseek-chat")
        self.assertIn("DeepSeek", resp.content)
        self.assertEqual(resp.usage["total_tokens"], 150)

        # Check call arguments
        call_kwargs = mock_post.call_args[1]
        self.assertEqual(call_kwargs["headers"]["Authorization"], "Bearer test-key")
        self.assertEqual(call_kwargs["json"]["model"], "deepseek-chat")

    @patch("httpx.Client.post")
    def test_gemini_provider(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "candidates": [{"content": {"parts": [{"text": "这是 Gemini 的对料分析报告"}]}}],
            "usageMetadata": {"promptTokenCount": 80, "candidatesTokenCount": 40, "totalTokenCount": 120},
        }
        mock_post.return_value = mock_resp

        provider = GeminiProvider(
            api_key="test-gemini-key",
            base_url="https://generativelanguage.googleapis.com",
            default_model="gemini-2.5-flash",
        )
        resp = provider.generate([
            {"role": "system", "content": "系统设定"},
            {"role": "user", "content": "当期心水"},
        ])

        self.assertEqual(resp.provider, "gemini")
        self.assertEqual(resp.model, "gemini-2.5-flash")
        self.assertIn("Gemini", resp.content)
        self.assertEqual(resp.usage["total_tokens"], 120)

        # Verify query params and payload conversion
        call_kwargs = mock_post.call_args[1]
        self.assertEqual(call_kwargs["params"]["key"], "test-gemini-key")
        self.assertIn("systemInstruction", call_kwargs["json"])
        self.assertEqual(call_kwargs["json"]["contents"][0]["role"], "user")

    @patch("httpx.Client.post")
    def test_anthropic_provider(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "content": [{"type": "text", "text": "这是 Claude 的精炼分析"}],
            "usage": {"input_tokens": 120, "output_tokens": 60},
        }
        mock_post.return_value = mock_resp

        provider = AnthropicProvider(
            api_key="test-claude-key",
            base_url="https://api.anthropic.com",
            default_model="claude-3-5-sonnet",
        )
        resp = provider.generate([
            {"role": "system", "content": "系统设定"},
            {"role": "user", "content": "分析预测"},
        ])

        self.assertEqual(resp.provider, "anthropic")
        self.assertEqual(resp.model, "claude-3-5-sonnet")
        self.assertIn("Claude", resp.content)
        self.assertEqual(resp.usage["total_tokens"], 180)

        # Verify headers and system param
        call_kwargs = mock_post.call_args[1]
        self.assertEqual(call_kwargs["headers"]["x-api-key"], "test-claude-key")
        self.assertEqual(call_kwargs["json"]["system"], "系统设定")

    def test_get_ai_client_factory(self):
        client_openai = get_ai_client("openai", api_key="k1", base_url="https://api.openai.com/v1")
        self.assertIsInstance(client_openai, OpenAIProvider)

        client_gemini = get_ai_client("gemini", api_key="k2")
        self.assertIsInstance(client_gemini, GeminiProvider)

        client_claude = get_ai_client("anthropic", api_key="k3")
        self.assertIsInstance(client_claude, AnthropicProvider)

    def test_analyze_scraped_data_orchestrator(self):
        mock_client = MagicMock()
        from app.services.ai.client import AIResponse
        mock_client.generate.return_value = AIResponse(
            content="### 综合对料结论\n本期重合生肖：马、龙\n精选特码：18, 30",
            provider="openai",
            model="deepseek-chat",
            usage={"total_tokens": 500},
            elapsed_sec=1.5,
        )

        sample_scraped = {
            "site_title": "顶尖大师",
            "modules": [
                {"id": 1, "name": "云顶心水", "type": "content", "content": "特肖：马"},
            ],
            "summary": {"total_modules": 1},
        }

        result = analyze_scraped_data(
            scraped_data=sample_scraped,
            prompt_id="consensus_synthesis",
            client=mock_client,
        )

        self.assertTrue(result.ok)
        self.assertEqual(result.provider, "openai")
        self.assertIn("综合对料结论", result.analysis)
        self.assertIn("重合生肖", result.analysis)

    def test_analyze_scraped_data_stream(self):
        mock_client = MagicMock()
        mock_client.default_model = "deepseek-chat"
        mock_client.generate_stream.return_value = iter(["### 澳门六合彩", "分析报告\n", "热肖：龙、马"])

        sample_scraped = {
            "site_title": "顶尖大师",
            "modules": [
                {"id": 1, "name": "云顶心水", "type": "content", "content": "特肖：马"},
            ],
            "summary": {"total_modules": 1},
        }

        events = list(
            analyze_scraped_data_stream(
                scraped_data=sample_scraped,
                prompt_id="macau_analyst_expert",
                period="262",
                client=mock_client,
            )
        )

        stages = [e.get("stage") for e in events]
        self.assertIn("started", stages)
        self.assertIn("delta", stages)
        self.assertIn("done", stages)

        deltas = "".join(e.get("delta", "") for e in events if e.get("stage") == "delta")
        self.assertEqual(deltas, "### 澳门六合彩分析报告\n热肖：龙、马")


if __name__ == "__main__":
    unittest.main()
