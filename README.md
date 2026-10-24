# ECommerceStore — simple Azure infrastructure

One Terraform root, one state, one variables file. Plain Terraform and Azure CLI;
no deployment wrappers, Python scripts, test framework, CI/CD or custom VNet.

## Resources

All services default to France Central, matching the existing subscription's SQL
Free region. Confirm SQL Free and DocumentDB Free capacity before applying. There
is no automatic fallback to a paid database tier.

| Resource | Count | Configuration |
| --- | ---: | --- |
| Resource group | 1 | `rg-ecommercestore-dev` |
| Container Apps environment | 1 | Consumption; Azure-managed network; live logs only |
| Container Apps | Up to 4 | Products, BFF, Web, Users; public HTTPS; 0–1 replicas each |
| SQL logical server | 1 | Password authentication; public endpoint |
| SQL database | 1 | `products`; Free offer; serverless; pause at monthly free limit |
| DocumentDB cluster | 1 | MongoDB-compatible; Free; 32 GB; no HA |
| Photo storage account | 1 | Standard LRS / Hot |
| Photo container | 1 | `photos`; anonymous blob reads; authenticated writes |

This is **11 core resources with all four apps enabled**, plus two required database
firewall rules: **13 Terraform resource instances**. The rules allow Azure services
to attempt connections, including other subscriptions; database authentication is
still required. There are no Internet-wide database firewall rules or outbound IP scripts.

| Apps in `app_images` | Resources on a fresh deployment |
| --- | ---: |
| None — first apply | 9 |
| Products | 10 |
| Products + BFF | 11 |
| Products + BFF + Web | 12 |
| All four, including Users later | 13 |

Counts exclude provider registrations, Azure-managed supporting resources and the
existing state storage. Resource names and passwords stay stable between runs.

## 1. Prepare

Install Terraform 1.13.1+ (below 2.0), Azure CLI and PowerShell 7. Providers are pinned
in `.terraform.lock.hcl`. AzAPI is used only for SQL Free properties absent in AzureRM.

The existing backend from the screenshot is configured in `terraform.tf`:

- Account: `stecomtfstatemb261011`
- Private container: `tfstate`
- New key: `ecommerce-store/simple-dev.terraform.tfstate`

Keep that account/container during cleanup. Your Azure CLI user needs **Storage Blob
Data Contributor** on state storage and permission to create resources and register
the providers listed in `terraform.tf`.

Finish cleaning the old application environment first. This root does not delete
or adopt old resources. Retained resources need explicit imports; never manage one
resource from two states. If the new backend key already exists, inspect its ownership
first. Do not migrate an old state into this root.

The photo account defaults to `stecproductsdevmb261013`, matching the Products seed
URLs. That name must be available to recreate or the retained account imported.
If you choose another name, update the application's seed URLs before deploying it.

```powershell
git clone https://github.com/MichalBoczula/ECommerceStore.Terraform.git
cd ECommerceStore.Terraform
Copy-Item terraform.tfvars.example terraform.tfvars
az login
az account set --subscription 'fcbf086b-8ce4-4ca5-a3d7-0c56489e25f6'
az account show --query '{subscription:name,id:id}' -o table
```

Check the subscription in `terraform.tfvars`. Leave `app_images = {}` initially.
Set two strong passwords and retain the same values for subsequent sessions:

```powershell
$env:TF_VAR_sql_admin_password = Read-Host 'SQL password' -AsSecureString | ConvertFrom-SecureString -AsPlainText
$env:TF_VAR_mongo_admin_password = Read-Host 'DocumentDB password' -AsSecureString | ConvertFrom-SecureString -AsPlainText
```

State and saved plans contain secrets despite masked CLI output. Local variables,
state and plan files are ignored by Git. A different password plans a rotation.
Optional `TF_VAR_dockerhub_token` supplies a read-only Docker Hub image-pull token;
`dockerhub_username` defaults to `mb0101`.

## 2. Create the foundation

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan "-out=deploy.tfplan"
```

Run the commands one at a time and stop if one fails. In PowerShell, quote the whole
`"-out=deploy.tfplan"` argument to keep it as one native command-line argument.

Review: expect **9 additions**, no deletion or migration of old infrastructure.
Apply the reviewed plan:

```powershell
terraform apply deploy.tfplan
terraform output
```

Every later change uses the same variables file and a fresh plan/apply. No `-target`,
deployment-stage scripts or `-auto-approve` are needed. The first apply creates the
databases, storage and empty ACA environment; it deploys no placeholder containers.

SQL Free pauses at its monthly limit. DocumentDB Free has no backup/restore or SLA
and may pause after 60 days of inactivity. Storage and active ACA usage can cost
money. Scale-to-zero removes idle replicas, not every subscription charge. Console
logs can be viewed live but are not retained.

## 3. Upload photos

`assets/` preserves the existing 60 WebP files and product mapping. Upload them with:

```powershell
az storage blob upload-batch --account-name (terraform output -raw photo_storage_account_name) --destination photos --source ./assets/photos --overwrite true --content-type image/webp
```

Azure CLI obtains the storage key using your signed-in user's management permissions;
no key is placed in the repository. Browsers read images directly from Blob Storage.
Products needs no Blob credentials. The existing S25 seed says Green while its photo
folder says Black; that application content correction remains separate.

## 4. Deploy Products next

Keep the same PowerShell session and database passwords used for the foundation.
Pull the repository update with `git pull --ff-only`. In your existing
`terraform.tfvars`, replace the `app_images = {}` entry with the following block;
keep your subscription, names and other existing settings:

```hcl
dockerhub_username = "mb0101"

app_images = {
  products = "docker.io/mb0101/product-catalog-api@sha256:dd92571adbbe889faacca4c0a72b4296a64e234c0ca9d57c9cf85b08bbd054d8"
}
```

The selected Linux/amd64 image is published from Products commit
`e81f779393780c95b878463beb710481e4d744c4`. Its [CI run](https://github.com/MichalBoczula/ProductsCatalog/actions/runs/38964842210)
passed its quality gate, image scan and publish step. The Docker Hub SHA tag and
`latest` resolved to this digest when checked on 2026-10-24. Pinning the digest means
a future `latest` publication cannot silently change this deployment.

Follow [Docker's personal access token instructions](https://docs.docker.com/security/access-tokens/personal-access-tokens/)
to create a token named `ecommerce-aca-pull` with read-only repository access.
For this public image, Public Read-only is sufficient. Enter the token locally:

```powershell
$env:TF_VAR_dockerhub_token = [System.Net.NetworkCredential]::new('', (Read-Host 'Docker Hub read-only token' -AsSecureString)).Password
```

Terraform puts the token in the Container App's `dockerhub-token` secret and
configures `docker.io` to use it with `dockerhub_username`. No extra Azure resource
is required. This credential is for ACA pulls; GitHub Actions' publishing credentials
are independent. Re-enter the same token in a new shell before later plans, or its
unset optional value will plan to remove authenticated pulls. Saved plans and remote
state contain secrets; keep them private.

Run these separately and stop on any failure:

```powershell
terraform validate
terraform plan "-out=deploy.tfplan"
```

With the foundation already applied and no configuration drift, expect
**1 to add, 0 to change, 0 to destroy**: `azurerm_container_app.app["products"]`.
The same app contains the registry secret and the SQL connection secret. If the
plan replaces a database or storage account, check the names/passwords before applying.

```powershell
terraform apply deploy.tfplan
```

Terraform supplies the SQL connection as an ACA secret, enables EF migrations and
configures independent liveness and database readiness probes. This disposable
environment uses the SQL administrator for both migrations and runtime access.

After apply, get the deployed URL and verify SQL readiness and the product list:

```powershell
$appUrls = terraform output -json app_urls | ConvertFrom-Json
$productsUrl = $appUrls.products
Invoke-RestMethod -Uri "$productsUrl/health/ready" -TimeoutSec 180
$phones = Invoke-RestMethod -Uri "$productsUrl/mobile-phones?amount=15" -TimeoutSec 180
$phones.Count
$phones | Select-Object name, mainPhoto
```

Readiness should return `Healthy`; the product response should contain the 15 seeded
phones and their Blob photo URLs. Open one photo URL as well. The first request can
be slow while ACA and SQL resume; if readiness returns 503, wait briefly and retry
the same request. Liveness alone does not prove database connectivity.

## 5. Add BFF, then Web

Keep Products and add `bff = "mb0101/ecommerce-store-bff-api:<published-commit-sha>"`.
Plan/apply. YARP receives the Products URL automatically. Verify
`/mobile-phones?amount=15` through BFF before proceeding.

**Before enabling Web, update its Nginx configuration in the application repo.**
The current image uses the Compose destination `http://bff:8080` and forwards the
frontend Host header. It needs the deployed BFF HTTPS URL, correct BFF Host/SNI and
the existing `/backend` prefix removal. Publish that updated image, then add
`web = "mb0101/ecommerce-store-web:<published-commit-sha>"` beside the existing entries.
Terraform does not rewrite Nginx or inject an environment variable the image cannot read.

Verify **Web → `/backend` → BFF → Products → SQL**, including photos. The current
BFF/UI also contain Users, Invoice and Payments features; complete registration,
cart, orders and checkout require those services later. Use demo data: the customer
selector is not authentication.

Users can later be added as `users = "mb0101/ecommerce-store-users-api:<published-commit-sha>"`.
Before claiming it works, verify its replica-set readiness probe, named indexes and
customer/history transaction rollback against DocumentDB. These have not been tested
in Azure. Terraform takes the connection string from DocumentDB rather than guessing it.

Do not remove existing image entries when adding another app: removal plans to
destroy that Container App. Leave entries present to retain the applications.

## Cleanup

Only when you intend to delete this disposable store, including all application data:

```powershell
terraform plan -destroy "-out=destroy.tfplan"
terraform apply destroy.tfplan
```

The independently managed `stecomtfstatemb261011/tfstate` backend remains. Cloning or
validating this repository creates no Azure resources.
