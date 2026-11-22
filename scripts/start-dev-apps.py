import os
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
    App("QA API", "START_QA_URL", optional=True),
)
MAX_ATTEMPTS = 6
REQUEST_TIMEOUT_SECONDS = 45
RETRY_DELAY_SECONDS = 5


def http_status(host: str, port: int | None, path: str) -> int:
    with closing(HTTPSConnection(host, port=port, timeout=REQUEST_TIMEOUT_SECONDS)) as client:
        client.request("GET", path)
        with client.getresponse() as response:
            return response.status


def warm_up(app: App) -> tuple[str, str]:
    origin = os.environ.get(app.secret, "").strip()
    if not origin:
        return ("Skipped" if app.optional else "Failed"), f"Missing {app.secret}"

    try:
        url = urlsplit(origin)
        host, port = url.hostname, url.port
    except ValueError:
        return "Failed", "Invalid HTTPS base URL"
    if (
        url.scheme != "https"
        or not host
        or url.username is not None
        or url.path not in ("", "/")
        or "?" in origin
        or "#" in origin
        or any(character.isspace() for character in origin)
    ):
        return "Failed", "Use an HTTPS base URL without credentials, path or query"

    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            status = http_status(host, port, app.path)
        except SSLCertVerificationError:
            return "Failed", "TLS certificate verification failed"
        except TimeoutError:
            detail = "Connection or response timed out"
        except (OSError, HTTPException, UnicodeError):
            detail = "Connection failed"
        else:
            detail = f"HTTP {status}"
            if 200 <= status < 300:
                return "Ready", f"{detail} on attempt {attempt}"
            if status not in (408, 429) and not 500 <= status < 600:
                break
        if attempt < MAX_ATTEMPTS:
            sleep(RETRY_DELAY_SECONDS)

    return "Failed", f"{detail} after {attempt} attempt(s)"


def main() -> int:
    with ThreadPoolExecutor(max_workers=len(APPS)) as pool:
        results = list(pool.map(warm_up, APPS))

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
