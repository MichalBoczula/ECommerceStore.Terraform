# Portfolio delivery plan

This is the consolidated MVP plan for the store, Pact API/Web and Knowledge API/Web.
The [release inventory](release-inventory.md) records the published candidates.
Record hosted acceptance only after reviewing the live Azure revisions and running
the relevant checks.

| Task | Work and acceptance |
| --- | --- |
| **TF/01 — Release inventory** | Record all eleven selected images and their successful CI publications, profile inputs and dependencies. Keep the existing Terraform root, state and full application map. |
| **TF/02 — Configuration guards** | Enforce digest pins for all applications; complete application dependency, publisher and feature configuration checks. Cover valid and invalid combinations with mocked plans. |
| **TF/03 — Initial deployment and verification** | Use the [initial deployment runbook](initial-deployment.md) to review a saved plan and deploy Store, Pact API/Web and Free Search. Verify serving revisions, Store flows, Pact access and a final no-change plan. |
| **TF/04 — Stripe runtime** | Follow the [Stripe runtime runbook](stripe-runtime.md) to enable sandbox Checkout and verify a signed webhook and durable payment confirmation on Azure. |
| **TF/05 — Fulfillment job** | Follow the [fulfillment rollout runbook](payment-fulfillment.md) to enable the scheduled job and verify Succeeded payment → Paid order → one invoice/PDF, including replay and retries. |
| **PACT/09 — First verified CI pilot** | Verify the Payments consumer contract against Invoice, publish immutable contracts/results and require the checks in source CI. Demonstrate a required-field failure and verified fix. |
| **PACT/10 — Remaining integrations** | Cover Invoice → Products, Web → APIs via BFF, registration gateways and remaining Payments → Invoice operations. Add scopes per publisher and track uncovered operations explicitly. Split the work by boundary. |
| **Pact final acceptance — PACT/11–12 + Pact Web WEB/12** | Complete report/graph acceptance and verify hosted filters, deep links, status distinctions, diagnostics and failure/fix navigation with real source-CI evidence. |
| **DOCS/01 — Current LiveDocs** | Verify the intended four producer bundles and hashes, update manifests, run import/publication and verify the deployed portal shows the intended source commits. |
| **RAG/DEP — Real Azure RAG** | Confirm Free Search and existing model deployments; index the chosen corpus with the matching embedding profile; evaluate live retrieval and answers; publish and deploy the matching API/Web release. |
| **RAG/DEMO — Final hosted demo** | Bound requests and show latency/token usage. Review answers, citations and validated JSON, and verify frontend/mobile/error behavior against the deployed corpus. |

## Reconciled baseline

The storefront redesign and Products price migration are merged and published.
The initial Azure rollout must use the selected pins and verify those behaviors.
The storefront acceptance stack still selects older backend images, so include
the selected release set in verification before marking the hosted flow complete.

Pact API PACT/07 publication has succeeded and its hosting configuration is merged.
Pact Web WEB/10 publication succeeded and WEB/11 hosting merged in Terraform PR #5;
those development steps are complete even where an older checklist says otherwise.
Hosted acceptance remains open. PACT/08 has a Payments consumer artifact; provider
replay and source CI publication remain PACT/09. Pact reporting/graph/history
features are implemented, with the real-evidence acceptance tracked above.

LiveDocs is published with source-pinned older reports. Both Knowledge applications
are published, with a labelled demo corpus in the baseline API image. LiveDocs
refresh, real indexing/model evaluation and public-demo acceptance remain open.
Search is already defined as an opt-in Free service in [`rag.tf`](../rag.tf).

## Rollout order

1. **A — TF/01–03:** Store, LiveDocs, Pact API/Web and Free Search infrastructure.
2. **B — TF/04–05:** Stripe test checkout and automatic order/invoice fulfillment.
3. **C — DOCS/01 → RAG/DEP:** the refreshed LiveDocs portal and real Knowledge API/Web,
   followed by RAG/DEMO acceptance.

PACT/09 can start once the registry is deployed and its publisher scopes are
verified. PACT/10 and hosted Pact acceptance then expand and prove its coverage.
All milestones use the existing state and operator-reviewed Terraform plans.
