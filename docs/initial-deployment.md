# TF/03 — Store, Pact and Search rollout

Use PowerShell 7.2+ in the existing Terraform checkout. Sign in to the subscription
from your private `terraform.tfvars` and keep the configured Azure Storage backend.
Run each block in order and resolve any error before continuing.

## 1. Review the current deployment and select the release

```powershell
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Update the existing checkout before continuing.' }
az account show --query '{name:name,id:id}' --output table
if ($LASTEXITCODE -ne 0) { throw 'Sign in to the deployment subscription.' }
terraform init -lockfile=readonly
if ($LASTEXITCODE -ne 0) { throw 'Initialize the configured backend before continuing.' }

$group = 'rg-ecommercestore-dev'
$names = @(az containerapp list --resource-group $group --query '[].name' --output tsv)
if ($LASTEXITCODE -ne 0) { throw 'Check the existing subscription and resource group.' }
foreach ($name in $names) {
    Write-Output $name
    az containerapp revision list --name $name --resource-group $group --query '[?properties.active].{revision:name,traffic:properties.trafficWeight,image:properties.template.containers[0].image}' --output table
    if ($LASTEXITCODE -ne 0) { throw "Revision inventory failed for $name." }
}
az search service list --resource-group $group --query '[].{name:name,sku:sku.name}' --output table
if ($LASTEXITCODE -ne 0) { throw 'Search inventory failed.' }
```

The `store-pact-search` profile selects the seven Store/LiveDocs apps, both Pact
apps and Free Search. Azure-mode Knowledge images are promoted in RAG/DEP after
indexing. Use `store-pact` if Search is intentionally deferred.

```powershell
$profile = 'store-pact-search'
('merge(var.app_images, local.release_profile_images["{0}"])' -f $profile) | terraform console
```

Review the printed candidate and copy it into the existing `app_images` map. For
`store-pact-search` set `knowledge_search_enabled = true`. If Azure already has
the named Search service and the plan proposes creating it, resolve state ownership
before applying. Keep your current passwords and registry pull credentials.

Add both publisher scopes to the existing private configuration and retain any
other valid scopes you already use.

```hcl
pact_publishers = {
  payments-ci = ["payments"]
  invoice-ci  = ["invoice"]
}
```

Use the [Pact publisher setup](../README.md#scoped-publisher-credentials) to supply
`TF_VAR_pact_publisher_token_sha256`. Store each raw token in its corresponding
repository's `PACT_PUBLISHER_TOKEN` secret for PACT/09.

## 2. Review and apply the saved plan

```powershell
terraform plan -input=false -out=tf03.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Create a successful fresh plan before continuing.' }
./scripts/Test-PortfolioDeployment.ps1 -PlanFile tf03.tfplan -Profile $profile
terraform show -no-color tf03.tfplan
```

The verifier checks the exact selected pins and accepts only additions and in-place
updates to selected apps and the selected Search service. Review the full saved
plan for changes to settings, secrets and ingress. Keep the plan private because
it contains deployment credentials. Resolve unrelated changes, replacements or
imports separately.

Apply the reviewed file, then verify the revisions receiving traffic.

```powershell
terraform apply tf03.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Resolve the apply failure before verifying.' }
./scripts/Test-PortfolioDeployment.ps1 -PlanFile tf03.tfplan -Profile $profile -Live
```

The live check reads Azure using the subscription and resource names from the
plan. It compares the image of each serving revision with the selected digest and
checks the planned Search service on Free. If traffic has yet to switch after an
apply, wait for the new revision to become ready and rerun the live check.

## 3. Verify Store and LiveDocs

```powershell
$ErrorActionPreference = 'Stop'
$urls = terraform output -json app_urls | ConvertFrom-Json
$release = Get-Content releases/portfolio.json -Raw | ConvertFrom-Json
$backend = "$($urls.web)/backend"

foreach ($key in @('products', 'users', 'orders', 'payments')) {
    $ready = Invoke-RestMethod "$($urls.$key)/health/ready" -TimeoutSec 180
    $status = if ($ready -is [string]) { $ready.Trim() } else { $ready.status }
    if ($status -ne 'healthy') { throw "$key readiness failed." }
}
$bff = Invoke-RestMethod "$backend/health" -TimeoutSec 180
if ($bff.Trim() -ne 'Healthy') { throw 'Web to BFF health check failed.' }

$phones = @(Invoke-RestMethod "$backend/mobile-phones?amount=15" -TimeoutSec 180)
$phones | Select-Object name, @{Name='Amount'; Expression={$_.price.amount}}, @{Name='Currency'; Expression={$_.price.currency}}
$phoneId = '3cf6e155-2a07-40e3-9c40-9be5a4c97d6c'
$phone = Invoke-RestMethod "$backend/mobile-phones/$phoneId" -TimeoutSec 180
if ($phone.id -ne $phoneId -or $phone.price.amount -le 0 -or -not $phone.price.currency) {
    throw 'The seeded iPhone 17 must have a positive price and currency.'
}
$photos = @($phone.commonDescription.mainPhoto) + @($phone.commonDescription.otherPhotos)
$photoBase = terraform output -raw photos_base_url
if ($LASTEXITCODE -ne 0 -or -not $photoBase -or $photos.Count -lt 2) { throw 'Expected the seeded phone gallery.' }
foreach ($photo in $photos) {
    if (-not $photo -or -not $photo.StartsWith($photoBase, [StringComparison]::Ordinal)) {
        throw 'The gallery must use the configured phone photo container.'
    }
    $image = Invoke-WebRequest $photo -Method Head -TimeoutSec 30
    if ([string]$image.Headers['Content-Type'] -notlike 'image/*') { throw 'Gallery photo failed.' }
}
$liveDocs = Invoke-RestMethod "$($urls.livedocs)/build-info.json" -TimeoutSec 180
if ($liveDocs.commitSha -ne $release.applications.livedocs.commitSha) { throw 'Unexpected LiveDocs build.' }
Start-Process "$($urls.web)/details/$phoneId"
```

Inspect the seeded catalog prices, then open the thumbnails and refresh the detail
URL in the browser. Confirm the displayed price matches the API and the images
show the selected phone.

### Check a demo customer, cart and order

This block creates a demo customer, order and payment reservation. The records
remain in the portfolio environment. The order stays in `Created` for this check.

```powershell
$externalId = "tf03-$([guid]::NewGuid())"
$address = @{ postalCode = '00-001'; city = 'Warsaw'; street = 'Main Street'; buildingNumber = '10'; apartmentNumber = '2' }
$registration = @{
    externalId = $externalId
    individual = @{
        firstName = 'Deployment'; lastName = 'Demo'; email = "$externalId@example.com"
        phone = '123456789'; billingAddress = $address; shippingAddress = $address
    }
}
$client = Invoke-RestMethod "$backend/registrations/customers" -Method Post -ContentType 'application/json' -Body ($registration | ConvertTo-Json -Depth 6) -TimeoutSec 180
$saved = Invoke-RestMethod "$backend/customers/external/$externalId" -TimeoutSec 180
if (-not $client.id -or $saved.id -ne $client.id) { throw 'Customer readback failed.' }

$cartBody = @{ lines = @(@{ productId = $phoneId; quantity = 1 }) } | ConvertTo-Json -Depth 4
$null = Invoke-RestMethod "$backend/shopping-carts/$($client.id)" -Method Put -ContentType 'application/json' -Body $cartBody -TimeoutSec 180
$order = Invoke-RestMethod "$backend/orders/client/$($client.id)" -Method Post -TimeoutSec 180
if (-not $order.id) { throw 'Order creation failed.' }
$readback = Invoke-RestMethod "$backend/orders/$($order.id)" -TimeoutSec 180
$cart = Invoke-RestMethod "$backend/shopping-carts/client/$($client.id)" -TimeoutSec 180
if ($readback.id -ne $order.id -or $readback.status -ne 'Created' -or
    $readback.lines.Count -ne 1 -or $readback.lines[0].quantity -ne 1 -or
    $readback.totalAmount -ne $phone.price.amount -or $readback.totalCurrency -ne $phone.price.currency -or
    -not $cart.PSObject.Properties['lines'] -or $cart.lines.Count -ne 0) {
    throw 'Order readback, total or cart clearing failed.'
}

$payment = Invoke-RestMethod "$backend/payments/$($order.id)/pay" -Method Post -TimeoutSec 180
$savedPayment = Invoke-RestMethod "$backend/payments/order/$($order.id)" -TimeoutSec 180
if (-not $payment.id -or $savedPayment.id -ne $payment.id -or $savedPayment.status -ne 'created') {
    throw 'Payment reservation readback failed.'
}
```

TF/04 and TF/05 cover Stripe confirmation and automatic invoice fulfillment.

## 4. Verify Pact access and Terraform convergence

```powershell
$null = Invoke-WebRequest "$($urls.pact_web)/health/ready" -TimeoutSec 180
$dashboard = Invoke-WebRequest "$($urls.pact_web)/verifications" -TimeoutSec 180
if ([string]$dashboard.Headers['Content-Type'] -notlike 'text/html*') { throw 'Pact Web deep link failed.' }
$page = Invoke-RestMethod "$($urls.pact_web)/backend/api/applications?pageSize=1" -TimeoutSec 180
if (-not $page.PSObject.Properties['items']) { throw 'Pact Web registry proxy failed.' }
```

A valid empty registry page passes. From a machine that can reach Pact API ingress,
use the existing [Pact verifier](https://github.com/MichalBoczula/ECommerceStore.Pact/blob/main/scripts/verify-deployment.py)
for both publisher scopes. Supply the existing token for each scope. Set
`$pactCheckout` to your local Pact repository path in the same PowerShell session.

```powershell
foreach ($application in @('payments', 'invoice')) {
    $env:PACT_PUBLISHER_TOKEN = Read-Host "$application publisher token" -MaskInput
    try {
        python "$pactCheckout/scripts/verify-deployment.py" --url $urls.pact --application $application
        if ($LASTEXITCODE -ne 0) { throw "Pact verification failed for $application." }
    }
    finally {
        Remove-Item Env:PACT_PUBLISHER_TOKEN
    }
}
```

The verifier checks registry/Mongo readiness, anonymous write rejection and scoped
authentication through a validation request that stores zero records. Real
provider/consumer evidence follows in PACT/09.

From the Terraform root, rerun a full plan using the same private inputs.

```powershell
terraform plan -input=false -detailed-exitcode
if ($LASTEXITCODE -ne 0) { throw 'Expected a successful no-change plan.' }
```

Record the release/profile, live revision results, smoke outcomes and no-change
result. The verification summary contains the relevant image and revision
identities for review.
