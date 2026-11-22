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
| `ca-ecommercestore-ba-dev` | `START_BA_URL` (optional) | `/health/ready` |
| QA API when deployed | `START_QA_URL` (optional) | `/health/ready` |

Once the workflow is on `main`, open **Actions → Start DEV apps → Run workflow**.
It sends parallel GETs to the configured applications. HTTP traffic wakes
deployed revisions that have scaled to zero. The workflow retries cold-start
timeouts, connection failures, HTTP 408, 429, and 5xx responses up to six
attempts per app. It reports ready on a 2xx response.

The job summary shows application names and results. A missing required secret
or a failed configured probe makes the job fail. Missing BA and QA URLs are
reported as skipped. Logs and summaries omit URLs and response bodies.
Use origins reachable from a GitHub-hosted runner. Access to each endpoint is
controlled by its Azure ingress and application settings.

Run this workflow before a DEV demo or smoke test. Azure HTTP scaling may put
idle applications back to sleep afterward. The Payments fulfillment job
executes on its Azure schedule.
