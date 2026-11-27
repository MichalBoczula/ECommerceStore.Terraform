import os
import re
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from http.client import HTTPException, HTTPSConnection
from pathlib import Path
from ssl import SSLCertVerificationError
from time import sleep
from typing import NamedTuple
from urllib.parse import urlsplit


class App(NamedTuple):
    name: str
    secret: str
    path: str = "/health/ready"
    optional: bool = False
    bearer_challenge: bool = False


ORCHESTRATOR_WEB = "ca-ecommercestore-ao-web-dev"
ORCHESTRATOR_WEB_SECRET = "START_AGENT_ORCHESTRATOR_WEB_URL"
MCP = "ca-ecommercestore-mcp-dev"
DEFAULT_ORIGIN_APPS = {
    ORCHESTRATOR_WEB_SECRET: ORCHESTRATOR_WEB,
    "START_MCP_URL": MCP,
}
ACA_DOMAIN = r"[a-z0-9-]+\.[a-z0-9-]+\.azurecontainerapps\.io"

APPS = (
    App("ca-ecommercestore-products-dev", "START_PRODUCTS_URL"),
    App("ca-ecommercestore-bff-dev", "START_BFF_URL", "/health"),
    App("ca-ecommercestore-web-dev", "START_WEB_URL", "/"),
    App("ca-ecommercestore-users-dev", "START_USERS_URL"),
    App("ca-ecommercestore-orders-dev", "START_ORDERS_URL"),
    App("ca-ecommercestore-payments-dev", "START_PAYMENTS_URL"),
    App("ca-ecommercestore-livedocs-dev", "START_LIVEDOCS_URL"),
    App("ca-ecommercestore-pact-dev", "START_PACT_URL"),
    App("ca-ecommercestore-pact-web-dev", "START_PACT_WEB_URL"),
    App("ca-ecommercestore-ka-api-dev", "START_KNOWLEDGE_API_URL"),
    App("ca-ecommercestore-ka-web-dev", "START_KNOWLEDGE_WEB_URL"),
    App("ca-ecommercestore-ba-dev", "START_BA_URL", optional=True),
    App(ORCHESTRATOR_WEB, ORCHESTRATOR_WEB_SECRET, optional=True),
    App(
        "ca-ecommercestore-ao-api-dev",
        ORCHESTRATOR_WEB_SECRET,
        "/api/v1/runs?limit=1",
        optional=True,
        bearer_challenge=True,
    ),
    App(MCP, "START_MCP_URL", "/health/live", optional=True),
    App("ca-ecommercestore-qa-dev", "START_QA_URL", optional=True),
)
MAX_ATTEMPTS = 6
REQUEST_TIMEOUT_SECONDS = 45
RETRY_DELAY_SECONDS = 5


def https_address(origin: str) -> tuple[str, int | None]:
    try:
        url = urlsplit(origin)
        host, port = url.hostname, url.port
    except ValueError as error:
        raise ValueError("Invalid HTTPS base URL") from error
    if (
        url.scheme != "https"
        or not host
        or url.username is not None
        or url.path not in ("", "/")
        or "?" in origin
        or "#" in origin
        or any(character.isspace() for character in origin)
    ):
        raise ValueError("Use an HTTPS base URL without credentials, path or query")
    return host, port


def resolve_origins() -> dict[str, str]:
    origins = {app.secret: os.environ.get(app.secret, "").strip() for app in APPS}
    for app in APPS:
        try:
            host, port = https_address(origins[app.secret])
        except ValueError:
            continue
        name, _, domain = host.partition(".")
        if name != app.name or port not in (None, 443) or not re.fullmatch(ACA_DOMAIN, domain):
            continue
        for secret, app_name in DEFAULT_ORIGIN_APPS.items():
            origins[secret] = origins[secret] or f"https://{app_name}.{domain}"
        break
    return origins


def http_response(host: str, port: int | None, path: str) -> tuple[int, str]:
    with closing(HTTPSConnection(host, port=port, timeout=REQUEST_TIMEOUT_SECONDS)) as client:
        client.request("GET", path)
        with client.getresponse() as response:
            return response.status, response.getheader("WWW-Authenticate", "")


def warm_up(app: App, origin: str) -> tuple[str, str]:
    if not origin:
        return ("Skipped" if app.optional else "Failed"), f"Missing {app.secret}"
    try:
        host, port = https_address(origin)
    except ValueError as error:
        return "Failed", str(error)

    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            status, challenge = http_response(host, port, app.path)
        except SSLCertVerificationError:
            return "Failed", "TLS certificate verification failed"
        except TimeoutError:
            detail = "Connection or response timed out"
        except (OSError, HTTPException, UnicodeError):
            detail = "Connection failed"
        else:
            detail = f"HTTP {status}"
            if status == 401 and app.bearer_challenge and challenge.strip().lower() == "bearer":
                return "Ready", f"{detail} Bearer challenge on attempt {attempt}"
            if 200 <= status < 300 and not app.bearer_challenge:
                return "Ready", f"{detail} on attempt {attempt}"
            if status not in (408, 429) and not 500 <= status < 600:
                break
        if attempt < MAX_ATTEMPTS:
            sleep(RETRY_DELAY_SECONDS)

    return "Failed", f"{detail} after {attempt} attempt(s)"


def main() -> int:
    origins = resolve_origins()
    with ThreadPoolExecutor(max_workers=len(APPS)) as pool:
        results = list(pool.map(warm_up, APPS, (origins[app.secret] for app in APPS)))

    rows = ["## DEV Container Apps", "", "| Application | Result | Details |", "| --- | --- | --- |"]
    for app, (result, detail) in zip(APPS, results):
        rows.append(f"| {app.name} | {result} | {detail} |")
    summary = "\n".join(rows)
    print(summary)
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary_path).open("a", encoding="utf-8") as report:
            report.write(f"{summary}\n")
    return int(any(result == "Failed" for result, _ in results))


if __name__ == "__main__":
    raise SystemExit(main())
