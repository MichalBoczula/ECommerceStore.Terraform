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

## 5. Deploy BFF

After Products readiness, Swagger and photo checks succeed, keep its image entry
and add BFF to the same `app_images` block in your existing `terraform.tfvars`:

```hcl
app_images = {
  products = "docker.io/mb0101/product-catalog-api@sha256:dd92571adbbe889faacca4c0a72b4296a64e234c0ca9d57c9cf85b08bbd054d8"
  bff      = "docker.io/mb0101/ecommerce-store-bff-api@sha256:ccf624855827c6ca0d59ffbf4b19459ad0d5899bbe997ba90ecabfd5e528873a"
}
```

The selected BFF image is Linux/amd64, published from commit
`3bbbe1c1eb7e76fc60b1bfeebeba613c9477ad7b`. Its [CI run](https://github.com/MichalBoczula/ECommerceStoreBFF/actions/runs/39057689508)
passed integration tests, the quality gate, container smoke test, image scan and
publication. Docker Hub's commit tag and `latest` resolved to this digest when
checked on 2026-10-24.

Terraform already sets port 8080, `/health` probes, 0–1 replicas and YARP's Products
destination to the Products HTTPS URL in this environment. The BFF needs no database
credentials of its own. This step adds one Container App and reuses the existing
environment and Docker Hub pull credentials.

```powershell
git pull --ff-only
terraform validate
terraform plan "-out=bff.tfplan"
```

Run commands separately. Keep the same database passwords and the working
`TF_VAR_dockerhub_token` from the Products deployment in this shell. `docker login`
alone does not supply Terraform's token, and GitHub Actions secrets do not populate
local variables. If starting a new shell, enter the same token as shown above.
Do not define `dockerhub_token` in `terraform.tfvars`, where it would override the
environment variable. Keep `dockerhub_username = "mb0101"`.

With Products already applied and no drift, expect **1 to add, 0 to change, 0 to
destroy**: `azurerm_container_app.app["bff"]`. Apply the new plan:

```powershell
terraform apply bff.tfplan
```

Verify the BFF process, then an actual request through BFF to Products and SQL:

```powershell
$appUrls = terraform output -json app_urls | ConvertFrom-Json
$productsUrl = $appUrls.products
$bffUrl = $appUrls.bff
Invoke-RestMethod "$productsUrl/health/ready" -TimeoutSec 180
Invoke-RestMethod "$bffUrl/health" -TimeoutSec 180
$phones = Invoke-RestMethod "$bffUrl/mobile-phones?amount=15" -TimeoutSec 180
$phones.Count
$phones | Select-Object name, mainPhoto
Start-Process "$bffUrl/scalar/products"
```

Both health requests should return `Healthy`; the product count should be 15.
The first Products readiness request warms SQL before testing the gateway. A BFF
health result alone does not check any upstream API. The product route remains
`/mobile-phones`; `/api/products` is a prefix only for the proxied OpenAPI document
at `/api/products/swagger/v1/swagger.json`. The BFF serves Scalar at
`/scalar/products`, rather than its own Swagger UI. Users, Orders and Payments
routes require their applications to be deployed later.

## 6. Deploy Web

The Web image supports the `BFF_URL` container setting. Terraform supplies
`http://ca-ecommercestore-bff-dev`, using ACA's built-in app-name service discovery
inside the shared environment. Microsoft documents this address format for
[calls between apps in the same environment](https://learn.microsoft.com/en-us/azure/container-apps/connect-apps#call-a-container-app-by-name).
The app-name HTTP endpoint uses ingress port 80; ACA routes it to BFF's target
port 8080. Its behavior is separate from the public FQDN's HTTPS redirect setting.

The official Nginx image renders its template at startup, removes `/backend` when
proxying and sends the BFF Host. Browser access remains HTTPS with same-origin API
requests. There is no custom startup script or per-environment Angular rebuild.
Docker Compose retains its default `http://bff:8080` destination.

Keep both existing applications and add Web in your local `terraform.tfvars`:

```hcl
app_images = {
  products = "docker.io/mb0101/product-catalog-api@sha256:dd92571adbbe889faacca4c0a72b4296a64e234c0ca9d57c9cf85b08bbd054d8"
  bff      = "docker.io/mb0101/ecommerce-store-bff-api@sha256:ccf624855827c6ca0d59ffbf4b19459ad0d5899bbe997ba90ecabfd5e528873a"
  web      = "docker.io/mb0101/ecommerce-store-web@sha256:b8738eb18d2de58045a408c1b1df79b04bb9ba673bec848983031a03cc19773d"
}
```

The selected Linux/amd64 Web image is published from commit
`754c7ac434c74c2010bc0f61f68c32977228323d`. Its [CI run](https://github.com/MichalBoczula/ecommerce-store-web/actions/runs/40115947706)
passed build, contract drift, dependency audit, unit coverage, browser acceptance,
container smoke and image scan before publication. The digest was checked on
2026-10-24.

Keep the same database passwords and working `TF_VAR_dockerhub_token` in your shell.
Run these commands separately after pulling the repository update:

```powershell
git pull --ff-only
terraform validate
terraform plan "-out=web.tfplan"
```

With Products and BFF already applied and no drift, expect **1 to add, 0 to change,
0 to destroy**: `azurerm_container_app.app["web"]`. The web container uses port 80,
0–1 replicas and `/` for its startup, liveness and readiness probes. The root probe
checks the SPA, not the upstream services. Apply the fresh plan:

```powershell
terraform apply web.tfplan
```

### Repair an existing Web deployment using the BFF HTTPS address

If Web returns Nginx 502 responses and its log reports
`upstream SSL certificate verify error: (20:unable to get local issuer certificate)`,
pull the current configuration and apply its internal BFF app-name address.
The existing Web image already supports this setting; keep all image entries and
the same database/Docker Hub credentials. No image rebuild is needed.

```powershell
git pull --ff-only
terraform validate
terraform plan "-out=web-connection.tfplan"
```

With Web already deployed and no other drift, expect **0 to add, 1 to change, 0 to
destroy**, updating only `azurerm_container_app.app["web"]`. The `BFF_URL` setting
changes from the BFF HTTPS FQDN to `http://ca-ecommercestore-bff-dev`.

```powershell
terraform apply web-connection.tfplan
```

### Verify the Web flow

Check the catalog through the Web origin, then open the storefront:

```powershell
$appUrls = terraform output -json app_urls | ConvertFrom-Json
$productsUrl = $appUrls.products
$webUrl = $appUrls.web
Invoke-RestMethod "$productsUrl/health/ready" -TimeoutSec 180
Invoke-RestMethod "$webUrl/backend/health" -TimeoutSec 180
$phones = Invoke-RestMethod "$webUrl/backend/mobile-phones?amount=15" -TimeoutSec 180
$phones.Count
$phones | Select-Object name, mainPhoto
Start-Process $webUrl
```

Expect both health responses to be `Healthy`, 15 products through the Web origin,
and catalog cards with their Blob photos in the browser. Follow a product details
link and refresh that page to check Nginx's SPA fallback. Cold ACA replicas and SQL
may make the first request slow; after a cold-start timeout, retry the request.

This verifies **Web → `/backend` → BFF → Products → SQL**, including photos. The current
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
