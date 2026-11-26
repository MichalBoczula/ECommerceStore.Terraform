import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import call, patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "start-dev-apps.py"
spec = importlib.util.spec_from_file_location("start_dev_apps", SCRIPT)
assert spec is not None and spec.loader is not None
warmup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(warmup)

DOMAIN = "test-env.westeurope.azurecontainerapps.io"
ORCHESTRATOR_WEB = f"https://ca-ecommercestore-ao-web-dev.{DOMAIN}"
ORCHESTRATOR_API = next(app for app in warmup.APPS if app.name == "ca-ecommercestore-ao-api-dev")
MCP = next(app for app in warmup.APPS if app.name == "ca-ecommercestore-mcp-dev")


class StartDevAppsTests(unittest.TestCase):
    def test_derives_origins_from_an_existing_container_app(self):
        env = {
            "START_WEB_URL": "https://store.example",
            "START_KNOWLEDGE_API_URL": f"https://ca-ecommercestore-ka-api-dev.{DOMAIN}",
        }
        with patch.dict(os.environ, env, clear=True):
            origins = warmup.resolve_origins()

        self.assertEqual(origins[ORCHESTRATOR_API.secret], ORCHESTRATOR_WEB)
        self.assertEqual(origins[MCP.secret], f"https://ca-ecommercestore-mcp-dev.{DOMAIN}")
        self.assertEqual(origins["START_WEB_URL"], env["START_WEB_URL"])

    def test_explicit_origin_takes_precedence_over_a_derived_origin(self):
        env = {
            "START_WEB_URL": f"https://ca-ecommercestore-web-dev.{DOMAIN}",
            "START_MCP_URL": "https://mcp.example",
        }
        with patch.dict(os.environ, env, clear=True):
            origins = warmup.resolve_origins()

        self.assertEqual(origins[MCP.secret], env["START_MCP_URL"])
        self.assertEqual(origins[ORCHESTRATOR_API.secret], ORCHESTRATOR_WEB)

    def test_skips_unconfigured_optional_apps_without_a_default_domain(self):
        with patch.dict(os.environ, {"START_WEB_URL": "https://store.example"}, clear=True):
            origins = warmup.resolve_origins()

        self.assertEqual(warmup.warm_up(ORCHESTRATOR_API, origins[ORCHESTRATOR_API.secret])[0], "Skipped")

    def test_uses_the_web_proxy_and_retries_until_the_api_returns_a_bearer_challenge(self):
        responses = [(502, ""), (401, "Bearer")]
        with patch.object(warmup, "http_response", side_effect=responses) as request, patch.object(warmup, "sleep"):
            result, detail = warmup.warm_up(ORCHESTRATOR_API, ORCHESTRATOR_WEB)

        self.assertEqual(result, "Ready")
        self.assertIn("attempt 2", detail)
        self.assertEqual(
            request.call_args_list,
            [call(f"ca-ecommercestore-ao-web-dev.{DOMAIN}", None, "/api/v1/runs?limit=1")] * 2,
        )

    def test_requires_a_bearer_challenge_for_the_api_only(self):
        checks = (
            (ORCHESTRATOR_API, 401, "", "Failed"),
            (ORCHESTRATOR_API, 200, "", "Failed"),
            (MCP, 401, "Bearer", "Failed"),
            (MCP, 200, "", "Ready"),
        )
        for app, status, challenge, expected in checks:
            with self.subTest(app=app.name, status=status):
                with patch.object(warmup, "http_response", return_value=(status, challenge)):
                    self.assertEqual(warmup.warm_up(app, ORCHESTRATOR_WEB)[0], expected)


if __name__ == "__main__":
    unittest.main()
