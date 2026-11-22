# Business Analyst API on DEV

Keep every current `app_images` entry and add `ba` using the immutable Docker Hub reference from the BA workflow's `image-reference` artifact. The Knowledge API uses its Azure runtime and pinned LiveDocs index.

Configure the BA Foundry agent version and Jira project in your local `terraform.tfvars`.

```hcl
ba_runtime = {
  foundry_project_endpoint = "https://example.services.ai.azure.com/api/projects/example"
  foundry_agent_name       = "ecommerce-business-analyst"
  foundry_agent_version    = "1"
  jira_site_url            = "https://example.atlassian.net"
  jira_email               = "integration@example.com"
  jira_project_key         = "STORE"
  jira_issue_type_id       = "10001"
  # Jira scoped tokens use jira_api_url = "https://api.atlassian.com/ex/jira/<cloud-id>".
}
```

Set `TF_VAR_ba_api_key`, `TF_VAR_ba_mongodb_uri` and `TF_VAR_ba_jira_api_token` in the shell. The MongoDB credential needs read/write access to `ecommerce_store_ba`. Continue to supply `TF_VAR_knowledge_api_key` and the existing store configuration.

Review the saved Terraform plan before apply. After apply, grant the `ba_principal_id` output **Azure AI User** on the Foundry project that contains the saved BA prompt agent. Retrieve the HTTPS URL from `app_urls.ba`. Set the same BA caller key for the CLI or supported MCP client. The BA repository's workflow guide covers the `CreateMobilePhone` acceptance run and the published QA handoff.
