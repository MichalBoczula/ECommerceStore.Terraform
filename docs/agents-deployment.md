# BA, Agent Orchestrator and MCP on DEV

Use the existing Azure Container Apps environment and keep all entries in your local `app_images` map. Replace the `ba` entry and add the other three entries.

```hcl
ba                     = "docker.io/mb0101/ecommerce-store-ba@sha256:420a26ea2b270e6779081f548d042dfde9ce3a90486d1a25072d2a28f5123c21"
agent_orchestrator_api = "docker.io/mb0101/ecommerce-store-agent-orchestrator-api@sha256:124ea68b98f7919f88e5c38a13533d5db0efa59e190ebf4bb7831a99cbc0a55a"
agent_orchestrator_web = "docker.io/mb0101/ecommerce-store-agent-orchestrator-web@sha256:cd32d3acfa37b8ba3f20ad598fb77fc2c839f6eae32510ff4f6717b1caf53466"
mcp                    = "docker.io/mb0101/ecommerce-store-mcp@sha256:2f745344636a89e47aed154d84d31c6652a72cb5ee7ff3cb6c88ef3ac9bc63e6"
```

This BA image contains the Foundry request fix and the Swagger descriptions. Keep the existing BA runtime and Knowledge snapshot configuration.

[BA image](https://github.com/MichalBoczula/ECommerceStore.BA/actions/runs/45735680474) · [Orchestrator API and worker image](https://github.com/MichalBoczula/ECommerceStore.AgentOrchestrator.Api/actions/runs/45735811493) · [Orchestrator Web image](https://github.com/MichalBoczula/ECommerceStore.AgentOrchestrator.Web/actions/runs/45735829165) · [MCP image](https://github.com/MichalBoczula/ECommerceStore.MCP/actions/runs/45737363187)

## Configure the Orchestrator

Add the following object to `terraform.tfvars`. Copy `issuer` and `jwks_url` from your identity provider's OpenID configuration and set `audience` to the `aud` claim expected in this API's access token.

```hcl
agent_orchestrator_auth = {
  issuer   = "https://identity.example/tenant/v2.0"
  audience = "<orchestrator-api-audience>"
  jwks_url = "https://identity.example/tenant/discovery/v2.0/keys"
}
```

The API requires an RS256 bearer with delegated `runs.read`, `runs.start` or `runs.review` for the matching operation. Web forwards the caller's authorization header to the internal API. The current Web release requires the caller to supply that bearer and has no sign-in flow in the browser.

The Orchestrator API and worker share the `ecommerce_store_agent_orchestrator` database on the DEV DocumentDB cluster by default. Supply `TF_VAR_agent_orchestrator_mongodb_uri` if using a dedicated MongoDB connection. The worker uses the API image, has one replica to drain MongoDB claims and runs independently of HTTP traffic.

To enable BA-to-QA authoring after deploying QA, set the following object using an actual **published** BA handoff for Products `GET /mobile-phones` or `GET /mobile-phones/{id}` and the criterion for opening a listed phone.

```hcl
agent_orchestrator_authoring = {
  qa_api_url      = "https://<qa-dev-host>"
  ba_session_id   = "<session UUID>"
  ba_run_id       = "<run UUID>"
  draft_sha256    = "<draft SHA-256>"
  criterion_index = 0
}
```

Set `TF_VAR_agent_orchestrator_qa_api_key` in the deployment shell alongside the existing `TF_VAR_ba_api_key`. Use `TF_VAR_agent_orchestrator_github_read_token` to read Storefront E2E artifacts and `TF_VAR_agent_orchestrator_langsmith_api_key` to enable worker tracing. With authoring unset, runs wait at `validating_handoff` for a configured worker.

## Plan and apply

Run in the existing Terraform checkout with the usual DEV `TF_VAR_*` inputs loaded. The initial plan should create Orchestrator API, Web, worker and MCP, and replace the BA image in place. Review the plan before applying.

```powershell
terraform plan '-out=agents-dev.tfplan'
terraform show 'agents-dev.tfplan'
terraform apply 'agents-dev.tfplan'
```

## Check the deployment

```powershell
$appUrls = terraform output -json app_urls | ConvertFrom-Json
Invoke-RestMethod -Uri "$($appUrls.ba)/health/ready" -TimeoutSec 180
Invoke-RestMethod -Uri "$($appUrls.agent_orchestrator_web)/health/ready" -TimeoutSec 180
Invoke-RestMethod -Uri "$($appUrls.mcp)/health/live" -TimeoutSec 180
terraform output -raw mcp_url
terraform output -raw agent_orchestrator_worker_name
```

Verify the BA Swagger shows operations with descriptions and use a fresh catalog session or retry the existing draft request against its pinned snapshot. For Orchestrator, use a valid `runs.read` access token to query `/api/v1/runs?limit=1` on the Web origin. The worker has no ingress. Check its revision and replica in the Azure portal. For MCP, connect MCP Inspector to `mcp_url`, list two phones and call the details tool for one. The public endpoint serves the store's catalog and routes through the existing BFF.

[BA run guide](https://github.com/MichalBoczula/ECommerceStore.BA/blob/main/docs/workflow.md) · [Orchestrator walkthrough](https://github.com/MichalBoczula/ECommerceStore.AgentOrchestrator.Api/blob/main/docs/demo.md) · [Azure Container Apps service discovery](https://learn.microsoft.com/azure/container-apps/connect-apps)
