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
| Container Apps | Up to 7 | Products, BFF, Web, Users, Orders/Invoices, Payments, LiveDocs; public HTTPS; 0–1 replicas each |
| SQL logical server | 1 | Password authentication; public endpoint |
| SQL database | 1 | `products`; Free offer; serverless; pause at monthly free limit |
| DocumentDB cluster | 1 | MongoDB-compatible; Free; 32 GB; no HA |
| Blob storage account | 1 | Existing photo account; Standard LRS / Hot |
| Photo container | 1 | `photos`; anonymous blob reads; authenticated writes |
| Invoice container | 1 | `invoices`; private; application uploads/downloads |
| Documentation container | 1 | `livedocs`; private; source bundles for later CI integration |

This is **16 core resources with all seven apps enabled**, plus two required database
firewall rules: **18 Terraform resource instances**. The rules allow Azure services
to attempt connections, including other subscriptions; database authentication is
still required. There are no Internet-wide database firewall rules or outbound IP scripts.

| Apps in `app_images` | Resources on a fresh deployment |
| --- | ---: |
| None — first apply | 11 |
| Products | 12 |
| Products + BFF | 13 |
| Products + BFF + Web | 14 |
| Products + BFF + Web + Users | 15 |
| Products + BFF + Web + Users + Orders/Invoices | 16 |
| All six store apps, including Payments | 17 |
| All seven, including LiveDocs | 18 |

Counts exclude provider registrations, Azure-managed supporting resources and the
existing state storage. Resource names and passwords stay stable between runs.
The invoice and LiveDocs containers are part of the foundation even while their
apps are disabled. The six-app store before the LiveDocs addition has 16 instances;
adding the documentation container and host takes that existing deployment to 18.
Plans upgrading older states also create any missing foundation containers.

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

Review: expect **11 additions**, no deletion or migration of old infrastructure.
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

Do not remove existing image entries when adding another app: removal plans to
destroy that Container App. Leave entries present to retain the applications.

## 7. Deploy Users

The existing foundation already contains the DocumentDB Free cluster and its Azure
services firewall rule. Adding Users creates **one Container App**, reusing that
cluster and the same ACA environment. BFF already has its Users destination and
routes; Web forwards those requests through `/backend`.

Pull the update and add the `users` entry to your existing `app_images` map in
`terraform.tfvars`. Keep all three deployed images and the same database passwords
and Docker Hub token:

```hcl
app_images = {
  products = "docker.io/mb0101/product-catalog-api@sha256:dd92571adbbe889faacca4c0a72b4296a64e234c0ca9d57c9cf85b08bbd054d8"
  bff      = "docker.io/mb0101/ecommerce-store-bff-api@sha256:ccf624855827c6ca0d59ffbf4b19459ad0d5899bbe997ba90ecabfd5e528873a"
  web      = "docker.io/mb0101/ecommerce-store-web@sha256:b8738eb18d2de58045a408c1b1df79b04bb9ba673bec848983031a03cc19773d"
  users    = "docker.io/mb0101/ecommerce-store-users-api@sha256:640624f8daa0cbe981e7bf475312564faa947b71c10e1dd343a279ca8cdaa51d"
}
```

The selected Linux/amd64 image is published from Users commit
`815cff4aa173dbc1ec36331c50b072f09b098df4`, including the reviewed
[DocumentDB readiness fix](https://github.com/MichalBoczula/ECommerceStoreUsers/pull/130).
Its [master CI run](https://github.com/MichalBoczula/ECommerceStoreUsers/actions/runs/40125453419)
passed build, formatting, generated contracts, unit/integration/acceptance suites,
coverage, secret scanning, the quality gate, image scanning and publication.
The Docker Hub full-commit tag resolved to this digest on 2026-10-24. Pinning it
keeps later image publications from silently changing the deployment.

Terraform supplies `MongoDbSettings__ConnectionString` through the app's existing
`database-connection` secret. It preserves the endpoint and options from Azure's
connection string and inserts the configured administrator username and URL-encoded
`mongo_admin_password`. This avoids carrying a previous password from AzureRM's
computed connection string into the app's plan during password updates. No connection
string or password needs copying from the portal. The database is
`ecommerce-store-users-db`. Startup initialization stays enabled and creates the
named collections/indexes. Readiness checks the writable replica set or router,
session support and an application-database ping. Liveness remains independent
of the database. This root does not use a preparation revision or outbound-IP script.

Run each command separately and stop on an error:

```powershell
git pull --ff-only
terraform fmt -check
terraform validate
terraform plan "-out=users.tfplan"
```

With Products, BFF and Web already deployed and no other drift, expect
**1 to add, 0 to change, 0 to destroy**: `azurerm_container_app.app["users"]`.
The existing database, storage and other Container Apps should remain untouched.

```powershell
terraform apply users.tfplan
$appUrls = terraform output -json app_urls | ConvertFrom-Json
$usersUrl = $appUrls.users
$bffUrl = $appUrls.bff
$webUrl = $appUrls.web
Invoke-RestMethod "$usersUrl/health/ready" -TimeoutSec 180
Start-Process "$usersUrl/swagger"
Start-Process "$bffUrl/scalar/users"
```

Expect `Healthy`. Check a Mongo-backed read through the Web origin:

```powershell
$clientId = [guid]::NewGuid().ToString()
$favorites = Invoke-RestMethod "$webUrl/backend/favorites/clients/$clientId" -TimeoutSec 180
$favorites.Count
```

A new client's favorites should return HTTP 200 and an empty list. This exercises
**Web → BFF → Users → DocumentDB**. On a cold-start timeout, retry the request.
If startup fails, view the Users console logs:

```powershell
az containerapp logs show --name ca-ecommercestore-users-dev --resource-group rg-ecommercestore-dev --type console --tail 100 --format text
```

### Recover from an inconsistent Users secret plan

If Mongo's password update completes but Users creation fails with
`Provider produced inconsistent final plan` for `.secret`, pull this configuration.
The Users secret now combines Azure's endpoint/options with this plan's password,
instead of relying on the password embedded in AzureRM's computed connection string.
The completed Mongo update is retained; no database recreation or state editing is
needed for this failure.

Some provider error diagnostics print secret values in plain text. If a password
was exposed, replace `mongo_admin_password` locally before generating the recovery
plan. Update whichever source supplies it (your ignored variables file or
`TF_VAR_mongo_admin_password`); keep the other database and Docker Hub credentials.
Do not paste passwords or full connection strings into troubleshooting output.

Run separately and stop on any failure. Use a fresh plan file:

```powershell
git pull --ff-only
terraform fmt -check
terraform validate
terraform plan "-out=users-retry.tfplan"
```

If you changed the Mongo password, expect **1 to add, 1 to change, 0 to destroy**:
Users creation and the Mongo password update. With the already-applied password
unchanged, expect **1 to add, 0 to change, 0 to destroy**. The error occurred before
Users creation, so this error alone does not require an import or an Azure deletion.

```powershell
terraform apply users-retry.tfplan
```

Then run the readiness and Web/BFF checks above. Never reuse `users.tfplan` after
a partial apply or a password/configuration change.

### Check a customer transaction

Readiness and a GET do not exercise writes. The following creates one demo customer
through Web/BFF and reads it back. Use demo values only; each run uses a new external
ID and leaves that demo customer in the database.

```powershell
$externalId = "aca-demo-$([guid]::NewGuid())"
$address = @{
  postalCode = '00-001'; city = 'Warsaw'; street = 'Main Street'
  buildingNumber = '10'; apartmentNumber = '20'
}
$body = @{
  externalId = $externalId
  individual = @{
    firstName = 'Demo'; lastName = 'Customer'
    email = 'demo@example.com'; phone = '123456789'
    billingAddress = $address; shippingAddress = $address
  }
  companies = @()
} | ConvertTo-Json -Depth 5
$customer = Invoke-RestMethod "$webUrl/backend/customers/" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
$savedCustomer = Invoke-RestMethod "$webUrl/backend/customers/external/$externalId" -TimeoutSec 180
$customer.id -eq $savedCustomer.id
```

Expect `True`. The create path writes the customer and its history in one
transaction. These commands have not been executed against your Azure cluster here;
they verify a successful create/read when you run them. Direct inspection of
current/history documents and forced-failure rollback remain separate hosted-database
checks; passing native MongoDB CI alone does not prove those Azure behaviors.

## 8. Deploy Orders / Invoices

The application repository is
[ECommerceStoreInvoice](https://github.com/MichalBoczula/ECommerceStoreInvoice).
Its Terraform app key is `orders`; its ACA name is `ca-ecommercestore-orders-dev`.
This root adds one private Blob container in the existing photo storage account and
supports one additional ACA. It reuses the existing DocumentDB cluster, firewall
rule and Consumption environment. There is no new Mongo cluster or storage account.

### Prepare the private container now

Keep your existing four entries in `app_images`, database passwords and Docker Hub
token. Pull this change and run each command separately:

```powershell
git pull --ff-only
terraform fmt -check
terraform validate
terraform plan "-out=invoice-storage.tfplan"
```

For an older four-app deployment missing both private containers, expect **2 to add,
0 to change, 0 to destroy**: `azurerm_storage_container.invoices` and
`azurerm_storage_container.livedocs`. If LiveDocs storage already exists in this
state, only the invoice container is added. The BFF Orders
destination is only added when `orders` is enabled, so this preparation does not
change or restart the existing apps. Review and apply:

```powershell
terraform apply invoice-storage.tfplan
terraform output invoice_storage_account_name
terraform output invoice_container_name
```

The account remains `stecproductsdevmb261013` unless you already changed its name;
the new container is `invoices`. Its access type is `private`, independently of the
public `photos` container. Connection strings are supplied to ACA as secrets and
are not exposed as Terraform outputs. State and saved plans still contain secrets.

### Enable the published application

The Blob storage and DocumentDB changes are implemented in
[Invoice PR #218](https://github.com/MichalBoczula/ECommerceStoreInvoice/pull/218).
The selected Linux/amd64 image is published from master commit `3b507354a2fc6fb5d1e9c0649c9553b3db4c494b`.
Its [CI run](https://github.com/MichalBoczula/ECommerceStoreInvoice/actions/runs/40190685483) passed the build, formatting, generated contracts,
unit/integration/acceptance suites, coverage, secret scanning, quality gate and image
scan before publication. Docker Hub's commit tag resolved to the pinned digest below
on 2026-10-25.

Keep the Products, BFF, Web and Users entries and add this line **inside the existing
`app_images` map** in your ignored `terraform.tfvars`:

```hcl
  orders = "docker.io/mb0101/ecommerce-store-invoice-api@sha256:fee09a35dcbd4f6fa823c468408dd1681b74f57c40a4d6213a7b2698f4152dfc"
```

Do not create a second map or replace your current variables file with the example.
Keep the same database passwords and Docker Hub pull token in this PowerShell
session. No Mongo or Blob connection string needs copying from the portal.

The app now accepts writable DocumentDB routers with sessions, initializes its
collections/indexes in its own database, and uploads PDFs into the private container
before publishing completed invoices. It uses the Chromium already installed in the
image. Production requires Blob configuration; local `file://` PDFs are reserved for
development/testing. Existing invoice reservations, failed-attempt cleanup and
ambiguous-completion recovery remain in place.

The container contract is:

| Setting | Value |
| --- | --- |
| Runtime | Production; HTTP port 8080; ACA terminates public HTTPS |
| Forwarded headers | `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true` for the proxy scheme |
| Mongo connection | `MongoDbSettings__ConnectionString`, secret; same password-stable URI as Users |
| Mongo database | `MongoDbSettings__DatabaseName=ecommerce-store-invoice-db` |
| Products API | `ExternalServices__ProductCatalog__BaseUrl`, existing Products HTTPS URL |
| Blob connection | `InvoiceStorage__ConnectionString`, secret from the existing storage account |
| Blob container | `InvoiceStorage__ContainerName=invoices` |
| Probes | `/health/live` for startup/liveness; `/health/ready` for readiness |
| Resources | 0.5 vCPU / 1 GiB for Chromium; 0–1 replicas |

The local name `users_connection_string` is reused for the shared cluster credentials;
the database selection stays separate through each application's configuration.
The Terraform database and account addresses are retained, so no existing data is
moved or recreated. The other apps keep their 0.25 vCPU / 0.5 GiB allocation.

When `orders` is enabled, Terraform sets
`ReverseProxy__Clusters__orders-cluster__Destinations__destination1__Address` on BFF
to the Orders HTTPS URL. The deployed BFF already routes `/shopping-carts`, `/orders`,
`/invoices`, `/client-data-versions`, `/orders-documentation` and the Orders OpenAPI
document. Web already forwards `/backend` to BFF; no new BFF routes or Web proxy
settings are needed for these existing API calls.

```powershell
git pull --ff-only
terraform fmt -check
terraform validate
terraform plan "-out=orders.tfplan"
```

After the private container preparation above, expect **1 to add, 1 to change, 0 to
destroy**: the Orders ACA is created and BFF gains its destination. The plan also
adds any missing foundation containers (`invoices` or `livedocs`).
Stop and inspect any other changes, especially password rotations or replacements.

```powershell
terraform apply orders.tfplan
```

### Verify the deployed application

If you deactivated existing ACA revisions overnight, reactivate them before these
checks. Warm Products/SQL first, then verify Orders readiness and its OpenAPI through
Web/BFF:

```powershell
$appUrls = terraform output -json app_urls | ConvertFrom-Json
Invoke-RestMethod "$($appUrls.products)/health/ready" -TimeoutSec 180
Invoke-RestMethod "$($appUrls.orders)/health/ready" -TimeoutSec 180
$ordersApi = Invoke-RestMethod "$($appUrls.web)/backend/api/orders/swagger/v1/swagger.json" -TimeoutSec 180
$ordersApi.info.title
$ordersApi.paths.'/invoices/{invoiceId}/pdf'.get.operationId
Start-Process "$($appUrls.bff)/scalar/orders"
```

Expect `Healthy` from both readiness checks and `DownloadInvoicePdf` as the operation
ID. The existing Web proxy and BFF route also forward the new PDF endpoint. After
creating an invoice in Scalar, copy its ID and download through the Web origin:

```powershell
$invoiceId = Read-Host 'Completed invoice ID'
Invoke-WebRequest "$($appUrls.web)/backend/invoices/$invoiceId/pdf" -OutFile "invoice-$invoiceId.pdf" -TimeoutSec 180
Start-Process "invoice-$invoiceId.pdf"
```

Direct anonymous Blob URLs return an error because `invoices` is private. The API
streams the PDF with `application/pdf`, a download filename and `private, no-store`.
The currently deployed Web image displays invoice metadata; adding its download
button remains a separate Web change. The API download above already uses Web/BFF.

Readiness and OpenAPI do not prove checkout or PDF storage. Verify a cart-to-order
transaction, paid-order invoice generation, Blob persistence and download through
Web/BFF. After restarting the Orders revision, download the same invoice again to
verify it survives container replacement. Keep current/history/snapshot consistency,
unique invoice reservation and failure rollback checks in the application suites.
Use the existing order status API for a demo Paid transition. Deploying the Payments
Pay/Get API alone does not confirm a Stripe payment or run invoice fulfillment;
see section 9. These Azure checks have not been run here. Readiness checks Mongo
connectivity/topology; it does not test Blob
permissions or PDF rendering. Ambiguous failed generations can retain orphan Blobs;
automatic orphan cleanup remains separate work.

### Check one demo checkout and invoice through Web/BFF

After the readiness checks above succeed, run each command separately and stop on
an error. This creates a demo client-data snapshot, one order and one invoice using
a real seeded product. It leaves those records in Mongo and the PDF in Blob storage.
The explicit `Paid` transition is a manual demo; it does not test Stripe or its worker.

```powershell
$backend = "$($appUrls.web)/backend"
$clientId = [guid]::NewGuid().ToString()
$phones = Invoke-RestMethod "$backend/mobile-phones?amount=1" -TimeoutSec 180
$productId = @($phones)[0].id
Invoke-RestMethod "$backend/shopping-carts/$clientId" -Method Post -TimeoutSec 180
$cartBody = @{ lines = @(@{ productId = $productId; quantity = 1 }) } | ConvertTo-Json -Depth 4
Invoke-RestMethod "$backend/shopping-carts/$clientId" -Method Put -ContentType 'application/json' -Body $cartBody -TimeoutSec 180
$order = Invoke-RestMethod "$backend/orders/client/$clientId" -Method Post -TimeoutSec 180
$order.id
$order.status
$clearedCart = Invoke-RestMethod "$backend/shopping-carts/client/$clientId" -TimeoutSec 180
@($clearedCart.lines).Count
```

Expect an order ID, `Created`, and zero remaining cart lines. Checkout calls Products
and writes the order, product snapshots and cleared cart in one Mongo transaction.
Next, supply demo invoice details and mark the order paid:

```powershell
$clientBody = @{
  clientName = 'Demo Customer'; addressEmail = 'demo@example.com'
  postalCode = '00-001'; city = 'Warsaw'; street = 'Main Street'
  buildingNumber = '10'; apartmentNumber = '20'
  phonePrefix = '48'; phoneNumber = '123456789'
} | ConvertTo-Json
Invoke-RestMethod "$backend/client-data-versions/$clientId" -Method Post -ContentType 'application/json' -Body $clientBody -TimeoutSec 180
Invoke-RestMethod "$backend/orders/$($order.id)/status" -Method Patch -ContentType 'application/json' -Body '{"status":"Paid"}' -TimeoutSec 180
$invoice = Invoke-RestMethod "$backend/invoices/$clientId/$($order.id)" -Method Post -TimeoutSec 180
$invoice.id
$invoice.storageUrl
Invoke-WebRequest "$backend/invoices/$($invoice.id)/pdf" -OutFile "invoice-$($invoice.id).pdf" -TimeoutSec 180
Start-Process "invoice-$($invoice.id).pdf"
```

The storage URL should point into the existing account's `invoices` container and
contain no SAS token. Open the downloaded PDF, then restart the Orders revision in
Azure and repeat the last two commands. The same invoice must remain downloadable.
These are hosted validation commands for you to run; CI tests use isolated native
Mongo, Azurite and HTTP fixtures rather than your Azure data.

## 9. Deploy Payments

The [Payments app](https://github.com/MichalBoczula/ECommerceStorePayments) is FastAPI
on Python 3.14, served by Uvicorn on port 8080. This step adds one Container App and
connects it to the existing DocumentDB cluster and Orders API. The application creates
its collections/indexes in the separate `ecommerce-store-payments-db` database.
There is no Terraform Mongo database resource to add: startup initializes it.

Keep all five existing entries in your `app_images` map and add this line inside
that same map in your ignored `terraform.tfvars`:

```hcl
  payments = "docker.io/mb0101/ecommerce-store-payments-api@sha256:154d9900a42689ad84758f87b7f481257a4829835c51ebdcf48f34950f1a2c6b"
```

This Linux/amd64 image is published from Payments main commit
`9663df14cb10886a32fa7850d1ca51537a3da009`. Its
[CI run](https://github.com/MichalBoczula/ECommerceStorePayments/actions/runs/36810479764)
passed source checks, all five suites, coverage, dependency audit, secret scan,
container smoke, image scan and publication. The full-commit Docker Hub tag resolved
to this digest when checked on 2026-10-25. No application source changes or image
rebuild are needed for this API deployment.

Terraform supplies:

| Setting | Value |
| --- | --- |
| ACA name | `ca-ecommercestore-payments-dev` |
| Runtime | `PAYMENTS_ENVIRONMENT=production`; port 8080; public HTTPS |
| Mongo connection | `PAYMENTS_MONGODB_CONNECTION_STRING`, ACA secret; same cluster credentials as Users/Orders |
| Mongo database | `PAYMENTS_MONGODB_DATABASE_NAME=ecommerce-store-payments-db` |
| Orders URL | `PAYMENTS_ORDERS_API_BASE_URL`, existing Orders HTTPS URL |
| Orders timeout | `PAYMENTS_ORDERS_API_TIMEOUT_SECONDS=30`, allowing for a cold replica |
| Stripe baseline | `PAYMENTS_STRIPE_ENABLED=false`; Pay/Get remains available |
| Probes | `/health/live` for startup/liveness; `/health/ready` for Mongo readiness |
| Resources | 0.25 vCPU / 0.5 GiB; 0–1 replicas |

The Payments entry requires `orders` to remain enabled. When Payments is enabled,
Terraform adds its HTTPS destination to BFF's existing `payments-cluster`. The deployed
BFF already forwards `/payments/...` and `/api/payments/openapi.json`; Web already
forwards `/backend` to BFF. No BFF or Web image change is needed for these API routes.

### Plan and apply

Keep the same database passwords and working Docker Hub pull token in this shell.
Run each command separately and stop on an error:

```powershell
git pull --ff-only
terraform fmt -check
terraform validate
terraform plan "-out=payments.tfplan"
```

With the previous five apps and current foundation applied, expect **1 to add, 1 to
change, 0 to destroy**: `azurerm_container_app.app["payments"]` is created, and BFF
gains its Payments destination. Review any other changes before applying; retain
the existing database passwords to avoid a rotation. An older state also gains the
LiveDocs archive container if it has not been created yet.

```powershell
terraform apply payments.tfplan
```

### Verify Mongo and Web/BFF routing

```powershell
$appUrls = terraform output -json app_urls | ConvertFrom-Json
Invoke-RestMethod "$($appUrls.orders)/health/ready" -TimeoutSec 180
Invoke-RestMethod "$($appUrls.payments)/health/ready" -TimeoutSec 180
$paymentsApi = Invoke-RestMethod "$($appUrls.web)/backend/api/payments/openapi.json" -TimeoutSec 180
$paymentsApi.info.title
Start-Process "$($appUrls.payments)/swagger"
Start-Process "$($appUrls.bff)/scalar/payments"
```

Payments readiness returns JSON with `status = healthy`; Orders returns `Healthy`.
OpenAPI should identify the Payments API. Readiness probes Mongo only; it does not
validate transactions, Orders, Stripe or invoice fulfillment. To exercise the real
Orders lookup and Mongo create/read, choose a demo order still in `Created` state
(the manually Paid order in section 8 is unsuitable), then run:

```powershell
$orderId = Read-Host 'Created demo order ID'
$backend = "$($appUrls.web)/backend"
$payment = Invoke-RestMethod "$backend/payments/$orderId/pay" -Method Post -TimeoutSec 180
$savedPayment = Invoke-RestMethod "$backend/payments/order/$orderId" -TimeoutSec 180
$payment.id -eq $savedPayment.id
$savedPayment.status
$repeatedPayment = Invoke-RestMethod "$backend/payments/$orderId/pay" -Method Post -TimeoutSec 180
$repeatedPayment.id -eq $payment.id
```

For a fresh valid order, expect `True`, `created`, `True`. The first Pay returns 201;
a repeat returns 200 with the same payment ID. This verifies **Web → BFF → Payments
→ Orders and DocumentDB**. It reserves a payment; it does not charge or mark the
order Paid. Native Mongo CI passed; these Azure runtime checks have not been run
here. Transaction-backed retries, history writes and webhook updates still need
hosted verification when enabling Stripe.

If startup or readiness fails, inspect the Payments logs without printing secrets:

```powershell
az containerapp logs show --name ca-ecommercestore-payments-dev --resource-group rg-ecommercestore-dev --type console --tail 100 --format text
```

### Stripe checkout and invoice fulfillment are a separate deployment step

This minimal API deployment deliberately follows the app's disabled Stripe baseline.
`POST /payments/{order_id}/checkout` returns 503 `checkout_disabled` until test checkout
is configured. The app requires a test API key, fixed frontend return URLs and an
endpoint-specific webhook signing secret. GitHub Actions secrets do not automatically
become ACA runtime settings. Register the Payments HTTPS webhook URL in Stripe test
mode and follow the app's [checkout](https://github.com/MichalBoczula/ECommerceStorePayments/blob/main/docs/stripe-checkout.md)
and [webhook](https://github.com/MichalBoczula/ECommerceStorePayments/blob/main/docs/stripe-webhooks.md)
runbooks before enabling it.

The API stores verified success and durable fulfillment work. It does not start the
one-shot fulfillment worker in the background. Automatic **Succeeded payment → Paid
order → invoice** additionally needs the app's
[scheduled ACA Job](https://github.com/MichalBoczula/ECommerceStorePayments/blob/main/docs/payment-fulfillment.md),
using the same image and Mongo/Orders settings. That job and Stripe runtime secrets
are outside this one-ACA Pay/Get step. Browser success navigation and API readiness
alone do not establish completed payment or invoice delivery.

## 10. Deploy the empty LiveDocs portal

The [LiveDocs repo](https://github.com/MichalBoczula/ECommerceStore.LiveDocs) already
publishes a stateless documentation image. It runs non-root Nginx on port 8080 and
serves Allure HTML generated during its image build. Its production manifest currently
contains development `v1` with no published projects, which is suitable for the first
empty deployment.

This step adds **one ACA and one private `livedocs` Blob container**, using the existing
resource group, ACA environment and photo storage account. The app uses 0.25 vCPU /
0.5 GiB and 0–1 replicas. It has independent startup/liveness and readiness probes,
needs no database, and is accessed directly at `/livedoc/` without a BFF route.

### Blob storage and the running container

The private container is an archive for source bundles: raw Allure results, feature
files, OpenAPI and other documentation inputs. Future CI will upload these bundles,
then LiveDocs will read selected bundles during its build and publish a new image.
Deploying that new digest updates the site.

The existing image does not read Blob at runtime. Its
[container contract](https://github.com/MichalBoczula/ECommerceStore.LiveDocs/blob/main/docs/container-contract.md)
requires no storage connection string, Azure identity or volume mount. Adding a
runtime Blob secret would not make uploads appear in this image. The empty host can
start while the archive is empty; upload permissions, service CI changes, manifest
imports and the first generated report are the next integration step.

For this rebuilt store, these new resources belong only to this consolidated root.
The application docs still describe the older split `ECommerceStore.LiveDocs.Terraform`
setup; do not apply those old roots to manage this deployment. Existing archives in
other accounts/states are neither imported nor deleted by this change. Retain their
data and URLs until an explicit migration if they contain documentation to keep.

### Select the image and deploy

Keep all six working store entries in your existing `app_images` map. Add this line
inside that same map in your ignored `terraform.tfvars`:

```hcl
  livedocs = "docker.io/mb0101/ecommerce-store-livedocs@sha256:91900df0a9a350eda089a267d6d9ed2a66ede6ff8313582fa14f594e481bd150"
```

The selected Linux/amd64 image comes from LiveDocs commit
`05d5e0e5420dd7452fb4c44be42e9b875ef88615`. Its
[main CI run](https://github.com/MichalBoczula/ECommerceStore.LiveDocs/actions/runs/39662767571)
passed the source/build, assembly, hosting and real Allure documentation checks,
dependency audit, secret scan, quality gate, production container smoke test, image
scan and publication. Docker Hub's full-commit tag resolved to this digest when
checked on 2026-10-25. No application image rebuild is needed for the empty portal.

Keep the same database passwords and Docker Hub pull token in your current shell.
Run each command separately and stop on an error:

```powershell
git pull --ff-only
terraform fmt -check
terraform validate
terraform plan "-out=livedocs.tfplan"
```

From the already-deployed six-app store before this change, expect **2 to add, 0 to
change, 0 to destroy**: `azurerm_storage_container.livedocs` and
`azurerm_container_app.app["livedocs"]`. Existing applications and BFF need no update.
If the archive container has already been created by this state, only the ACA is
added. After reviewing the plan:

```powershell
terraform apply livedocs.tfplan
```

### Verify the site and archive

```powershell
$appUrls = terraform output -json app_urls | ConvertFrom-Json
$liveDocsUrl = $appUrls.livedocs
Invoke-RestMethod "$liveDocsUrl/health/live" -TimeoutSec 180
Invoke-RestMethod "$liveDocsUrl/health/ready" -TimeoutSec 180
$build = Invoke-RestMethod "$liveDocsUrl/build-info.json" -TimeoutSec 180
$build.commitSha -eq '05d5e0e5420dd7452fb4c44be42e9b875ef88615'
Invoke-RestMethod "$liveDocsUrl/livedoc/catalog.json" -TimeoutSec 180 | ConvertTo-Json -Depth 8
Start-Process "$liveDocsUrl/livedoc/"
```

Both health routes should return HTTP 200, and the source commit comparison should
return `True`. The portal should open with an empty development v1. There are no
service Allure reports until the first real bundle is imported and a new image is
deployed. Readiness means the documentation host's site marker exists; it does not
mean service tests passed or the application APIs are healthy.

Check the storage target for the later CI integration:

```powershell
$archiveAccount = terraform output -raw livedocs_storage_account_name
$archiveContainer = terraform output -raw livedocs_container_name
az storage container show --account-name $archiveAccount --name $archiveContainer --query "{name:name,publicAccess:properties.publicAccess}" --output json
```

Expect account `stecproductsdevmb261013`, container `livedocs`, and no public access
(`publicAccess` is null). Azure CLI uses the signed-in user's management access to
obtain the account key, as with the existing photo upload commands; no key is printed
or committed. The source archive is private even though the generated site is public.
Its connection credentials are not Terraform outputs or runtime settings.

These Azure checks must be run after your apply; they have not been executed here.
If the app fails, inspect its console logs:

```powershell
az containerapp logs show --name ca-ecommercestore-livedocs-dev --resource-group rg-ecommercestore-dev --type console --tail 100 --format text
```

The archive container remains when the optional LiveDocs image entry is removed.
Removing that entry deletes the ACA; leave it present for normal scale-to-zero.
A full destroy of this root also deletes the shared account and documentation archive,
so retain needed bundles before deliberately destroying the complete store.

## Cleanup

Only when you intend to delete this disposable store, including all application data:

```powershell
terraform plan -destroy "-out=destroy.tfplan"
terraform apply destroy.tfplan
```

The independently managed `stecomtfstatemb261011/tfstate` backend remains. Cloning or
validating this repository creates no Azure resources.
