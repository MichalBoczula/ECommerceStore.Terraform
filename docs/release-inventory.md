# TF/01 — Shared release inventory

[`releases/portfolio.json`](../releases/portfolio.json) records the selected release
for each of the eleven applications. Each entry names the source repository,
full commit SHA, immutable Docker Hub reference, and CI run, attempt and publication
job. The initial inventory was checked against successful publication logs on
2026-11-05. It records published candidates; running Azure revisions are checked
separately in TF/03.

The application repositories own image builds, tests and publication. This root
owns infrastructure and operator-selected deployment inputs. Its existing
`app_images` variable still controls which applications Terraform manages. The
inventory does not change your private variables or enable any resource by itself.

## Select a profile

All profiles retain Products, BFF, Store Web, Users, Orders, Payments and LiveDocs.

| Profile | Adds | Required setting or prerequisite |
| --- | --- | --- |
| `store` | The seven base applications | Existing database credentials |
| `store-pact` | Pact API and Pact Web | Scoped publishers and matching token hashes |
| `store-pact-search` | Both Pact apps and Free Search | `knowledge_search_enabled = true`; Knowledge apps can wait for ingestion |
| `full-demo` | Both Pact apps and both Knowledge apps | `knowledge_runtime_mode = "demo"` and shared Knowledge API key. Search is optional; preserve an existing enabled setting. |
| `full-azure` | Both Pact apps and both Knowledge apps with real indexed documentation | A successful `knowledge-refresh-handoff/release.json`, Free Search, existing Azure OpenAI deployments, matching index/model settings and keys |

The `full-azure` profile is recorded as pending a refresh handoff. The checked-in
Knowledge API image contains a synthetic corpus and is only selected by the demo
profile. The Azure profile is excluded from the candidate image maps until an
indexed release has been reviewed and recorded.

## Review candidate inputs

Use this during TF/03 from your existing Terraform checkout, after initializing
its configured backend with the usual Azure CLI session. To prepare the first
deployment with Pact and Search, run in PowerShell:

```powershell
'merge(var.app_images, local.release_profile_images["store-pact-search"])' | terraform console
'local.release_inventory.profiles["store-pact-search"].terraformSettings' | terraform console
```

The first expression overlays the selected pins and preserves entries outside that
profile. Review the printed candidate against your existing map before copying it
into `app_images`. The second expression shows the profile's explicit Terraform
settings; review those separately. Selecting a profile never modifies a file or
applies a plan. Use `store-pact` when Search will be provisioned later, or `store`
for a store release without new Pact entries. Selecting `full-demo` intentionally
selects the demo Knowledge image and requires its matching mode.

Keep the existing database passwords, pull credentials if configured, and all
already-enabled applications. Do not copy a partial map from an old walkthrough:
removing an entry from `app_images` plans to remove its Container App. Review the
saved plan against the actual state before applying. Existing resources created
outside this state require an ownership check before any import or creation.

## Configuration inputs

Use the same existing backend (`stecomtfstatemb261011/tfstate`, key
`ecommerce-store/simple-dev.terraform.tfstate`). Keep SQL and Mongo passwords in
your current private inputs or use `TF_VAR_sql_admin_password` and
`TF_VAR_mongo_admin_password`. Preserve `TF_VAR_dockerhub_token` if authenticated
pulls are already configured. The inventory contains variable names only.

For the initial Payments → Invoice Pact pilot, add the publisher scopes at the
top level of your private `terraform.tfvars`:

```hcl
pact_publishers = {
  payments-ci = ["payments"]
  invoice-ci  = ["invoice"]
}
```

Supply one distinct matching SHA-256 hash per configured publisher through
`TF_VAR_pact_publisher_token_sha256`. Store the raw tokens in the corresponding
Payments and Invoice CI `PACT_PUBLISHER_TOKEN` secrets. Follow the
[Pact registry runbook](../README.md#12-pact-registry-optional) for creating hashes,
ingress, rotation and scope verification. The dashboard uses anonymous reads via
its same-environment proxy. PACT/09 wires the source CI publication; PACT/10 adds
publishers for the expanded integration coverage.

For Knowledge Web/API, supply the shared `TF_VAR_knowledge_api_key`. In Azure mode
also supply `TF_VAR_knowledge_openai_api_key`, the existing endpoint and chat and
embedding deployment names in `knowledge_models`, and the matching dimensions,
`knowledge_search_index` and `knowledge_embedding_revision`. Terraform creates the
Free Search service and passes a query key to the API. The Knowledge refresh
workflow owns ingestion, index schema, embeddings, and content. Its indexing
credentials are separate from the API's query key. Terraform references existing
model deployments; model provisioning is outside this release inventory.

## Update the inventory

Review the release update in a PR. Verify the successful source run and its
publication job or receipt, match the full commit and registry digest, then update
only the intended entries. Preserve the full application list. For LiveDocs,
review the selected producer commits in the pinned portal manifest; a newly built
portal can still contain older reports. For real RAG, review the refresh receipt's
matched API/LiveDocs images, corpus, index and embedding profile before promoting
that release. Keep the previous digests and matching configuration available for
rollback. Never commit private `.tfvars`, plans, state, or credentials.

`terraform test` checks that the inventory covers the supported applications,
that every image has a digest and CI identity, and that profile selection keeps the
core applications and separates the demo corpus from the Azure handoff.
