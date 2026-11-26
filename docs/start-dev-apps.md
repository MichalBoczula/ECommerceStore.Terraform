# Start DEV apps from GitHub Actions

Open **Settings → Secrets and variables → Actions → Secrets** in this repository.
Add each required secret as a **repository secret**. For its value, use the
application's HTTPS origin from `terraform output -json app_urls`. Paste the
base address, such as `https://<app-fqdn>`. The workflow adds the probe path.

| Container App | Secret | GET path |
| --- | --- | --- |
| `ca-ecommercestore-products-dev` | `START_PRODUCTS_URL` | `/health/ready` |
| `ca-ecommercestore-bff-dev` | `START_BFF_URL` | `/health` |
| `ca-ecommercestore-web-dev` | `START_WEB_URL` | `/` |
| `ca-ecommercestore-users-dev` | `START_USERS_URL` | `/health/ready` |
| `ca-ecommercestore-orders-dev` | `START_ORDERS_URL` | `/health/ready` |
| `ca-ecommercestore-payments-dev` | `START_PAYMENTS_URL` | `/health/ready` |
| `ca-ecommercestore-livedocs-dev` | `START_LIVEDOCS_URL` | `/health/ready` |
| `ca-ecommercestore-pact-dev` | `START_PACT_URL` | `/health/ready` |
| `ca-ecommercestore-pact-web-dev` | `START_PACT_WEB_URL` | `/health/ready` |
| `ca-ecommercestore-ka-api-dev` | `START_KNOWLEDGE_API_URL` | `/health/ready` |
| `ca-ecommercestore-ka-web-dev` | `START_KNOWLEDGE_WEB_URL` | `/health/ready` |
| `ca-ecommercestore-ba-dev` | `START_BA_API_URL` or `START_BA_URL` (optional) | `/health/ready` |
| `ca-ecommercestore-ao-web-dev` | `START_AGENT_ORCHESTRATOR_WEB_URL` (optional override) | `/health/ready` |
| `ca-ecommercestore-ao-api-dev` via Orchestrator Web | Same Orchestrator Web origin | `/api/v1/runs?limit=1` |
| `ca-ecommercestore-mcp-dev` | `START_MCP_URL` (optional override) | `/health/live` |
| QA API when deployed | `START_QA_URL` (optional) | `/health/ready` |

If an existing HTTPS origin uses its default Azure Container Apps hostname, the
workflow uses that environment domain for Orchestrator Web and MCP. To set an
explicit origin, use `app_urls.agent_orchestrator_web` or `app_urls.mcp` from
Terraform outputs in the corresponding secret.

Once the workflow is on `main`, open **Actions → Start DEV apps → Run workflow**.
It sends parallel GETs to the configured applications. HTTP traffic wakes
deployed revisions that have scaled to zero. The workflow retries cold-start
timeouts, connection failures, HTTP 408, 429, and 5xx responses up to six
attempts per app. The readiness probes expect a 2xx response. The probe for the
internal Orchestrator API makes an anonymous request through Web and expects
HTTP 401 with `WWW-Authenticate: Bearer`.

The job summary shows application names and results. A missing required secret
or a failed configured probe makes the job fail. Optional apps without a
configured or derived origin are reported as skipped. Logs and summaries omit
URLs and response bodies.
Use origins reachable from a GitHub-hosted runner. Access to each endpoint is
controlled by its Azure ingress and application settings.

Run this workflow before a DEV demo or smoke test. Azure HTTP scaling may put
idle applications back to sleep afterward. Terraform keeps the Orchestrator
worker running with one replica. The Payments fulfillment job executes on its
Azure schedule.
