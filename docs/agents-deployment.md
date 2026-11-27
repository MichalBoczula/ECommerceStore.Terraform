# BA, QA, Agent Orchestrator and MCP on DEV

Use the existing Azure Container Apps environment and keep all entries in your local `app_images` map. Replace the `ba` entry and add the other three entries.

```hcl
ba                     = "docker.io/mb0101/ecommerce-store-ba@sha256:420a26ea2b270e6779081f548d042dfde9ce3a90486d1a25072d2a28f5123c21"
agent_orchestrator_api = "docker.io/mb0101/ecommerce-store-agent-orchestrator-api@sha256:124ea68b98f7919f88e5c38a13533d5db0efa59e190ebf4bb7831a99cbc0a55a"
agent_orchestrator_web = "docker.io/mb0101/ecommerce-store-agent-orchestrator-web@sha256:cd32d3acfa37b8ba3f20ad598fb77fc2c839f6eae32510ff4f6717b1caf53466"
mcp                    = "docker.io/mb0101/ecommerce-store-mcp@sha256:2f745344636a89e47aed154d84d31c6652a72cb5ee7ff3cb6c88ef3ac9bc63e6"
```

This BA image contains the Foundry request fix and the Swagger descriptions. Keep the existing BA runtime and Knowledge snapshot configuration.

You can review the complete candidate image map with the current pins preserved before updating your file.

```powershell
'merge(var.app_images, {for name in ["ba", "agent_orchestrator_api", "agent_orchestrator_web", "mcp"] : name => local.release_inventory.applications[name].imageReference})' | terraform console
```

[BA image](https://github.com/MichalBoczula/ECommerceStore.BA/actions/runs/45735680474) · [Orchestrator API and worker image](https://github.com/MichalBoczula/ECommerceStore.AgentOrchestrator.Api/actions/runs/45735811493) · [Orchestrator Web image](https://github.com/MichalBoczula/ECommerceStore.AgentOrchestrator.Web/actions/runs/45735829165) · [MCP image](https://github.com/MichalBoczula/ECommerceStore.MCP/actions/runs/45737363187)

## Deploy QA on DEV

Add the QA digest to the existing `app_images` map alongside the BA deployment.

```hcl
qa = "docker.io/mb0101/ecommerce-store-qa@sha256:e567c44c6aaf14619fdce2484fe0130f0dc43edb4168fc93c054e04b1f044db2"
```

Supply `TF_VAR_qa_api_key` as the shared QA API key and
`TF_VAR_qa_e2e_github_token` as a GitHub token with Contents and Pull requests
write access scoped to `ECommerceStore.E2E`. QA uses the existing BA key and
the `ecommerce_store_qa` database on the shared DEV DocumentDB cluster. Set
`TF_VAR_qa_mongodb_uri` for a dedicated cluster.

After apply, use `app_urls.qa` from `terraform output -json app_urls` for
`START_QA_URL` in the warm-up workflow. Use the same origin for `/swagger`
and `/health/ready`.

[QA image](https://github.com/MichalBoczula/ECommerceStore.QA/actions/runs/45584621589) · [QA API guide](https://github.com/MichalBoczula/ECommerceStore.QA#author-a-storefront-bdd-test)

## Configure the Orchestrator

Add the following object to `terraform.tfvars`. Copy `issuer` and `jwks_url` from your identity provider's OpenID configuration and set `audience` to the `aud` claim expected in this API's access token.

```hcl
agent_orchestrator_auth = {
  issuer   = "https://identity.example/tenant/v2.0"
  audience = "<orchestrator-api-audience>"
  jwks_url = "https://identity.example/tenant/discovery/v2.0/keys"
}
```

The API requires an RS256 bearer with delegated `runs.read`, `runs.start` or `runs.review` for the matching operation. Web forwards the caller's authorization header to the internal API.

For browser sign-in, use the published Web image that includes MSAL and
register a single-tenant Entra SPA with the three delegated API permissions.
Add the HTTPS Web origin with `/auth/redirect` for sign-in and `/` for
sign-out. Set the SPA application client ID in the local deployment file.

```hcl
agent_orchestrator_web_entra_client_id = "<Web SPA application client ID>"
```

Terraform passes the tenant from the configured v2 issuer and the API
application ID from the audience to Web. Use the API application ID URI
`api://<API application client ID>` in Entra. The Web image reference comes
from the CI `image-reference` artifact.

[Orchestrator Web configuration](https://github.com/MichalBoczula/ECommerceStore.AgentOrchestrator.Web#enable-entra-sign-in)

The Orchestrator API and worker share the `ecommerce_store_agent_orchestrator` database on the DEV DocumentDB cluster by default. Supply `TF_VAR_agent_orchestrator_mongodb_uri` if using a dedicated MongoDB connection. The worker uses the API image, has one replica to drain MongoDB claims and runs independently of HTTP traffic.

To enable BA-to-QA authoring after deploying QA, set the following object using an actual **published** BA handoff for Products `GET /mobile-phones` or `GET /mobile-phones/{id}` and the criterion for opening a listed phone.

```hcl
agent_orchestrator_authoring = {
  ba_session_id   = "<session UUID>"
  ba_run_id       = "<run UUID>"
  draft_sha256    = "<draft SHA-256>"
  criterion_index = 0
}
```

The worker connects to managed QA through its internal Container Apps address
and shares `TF_VAR_qa_api_key`. For an external QA deployment, set
`qa_api_url` to its HTTPS origin and supply `TF_VAR_agent_orchestrator_qa_api_key`.
Use `TF_VAR_agent_orchestrator_github_read_token` to read Storefront E2E
artifacts and `TF_VAR_agent_orchestrator_langsmith_api_key` to enable worker
tracing. With authoring unset, runs wait at `validating_handoff` for a
configured worker.

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

## Enable MCP sandbox checkout on DEV

Pin `app_images.mcp` to a published checkout-capable image. Register a Microsoft Entra v2 API dedicated to the MCP server. Use the default Application ID URI and expose the delegated `mcp.checkout` scope. Grant the scope to the client that signs in. Add the directory tenant ID and the MCP API application client ID to `terraform.tfvars`.

```hcl
mcp_checkout_auth = {
  tenant_id     = "<directory tenant ID>"
  api_client_id = "<MCP API application client ID>"
}
```

Supply a stable random key of at least 32 characters through `TF_VAR_mcp_checkout_identity_key` in the session running Terraform. Keep the key across deployments to preserve customer and order access. Checkout requires the existing Stripe Sandbox configuration and `payments_fulfillment_enabled = true`. Terraform sets the public MCP resource URL and passes the key as a Container Apps secret.

After applying, use `terraform output -raw mcp_url` with a delegated MCP token. Run a purchase with the synthetic profile, complete the payment on the hosted Stripe Sandbox page, then verify the completed invoice PDF. [MCP checkout and Code Mode](https://github.com/MichalBoczula/ECommerceStore.MCP#enable-sandbox-checkout)

[BA run guide](https://github.com/MichalBoczula/ECommerceStore.BA/blob/main/docs/workflow.md) · [Orchestrator walkthrough](https://github.com/MichalBoczula/ECommerceStore.AgentOrchestrator.Api/blob/main/docs/demo.md) · [Azure Container Apps service discovery](https://learn.microsoft.com/azure/container-apps/connect-apps)
