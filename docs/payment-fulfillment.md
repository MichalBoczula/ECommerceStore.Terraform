# TF/05 Payment fulfillment rollout

This opt-in Container Apps Job processes verified payment receipts in the existing
Payments database. It uses the selected Payments image and the same Orders API
settings. One replica runs a batch of up to 100 items every five minutes (UTC).
The job uses the existing Consumption environment, a 30-minute execution replica
timeout and one replica retry. Stripe API and signing credentials stay with the
Payments HTTP app. The schedule processes all eligible work in the shared demo
database, including outstanding receipts from TF/04.

## Prepare the sandbox order

Complete [TF/04](stripe-runtime.md) first. Pick a sandbox order whose payment is
`succeeded`, whose order is still `Created`, and whose completed invoice is absent.
Run the following from the existing Terraform checkout in PowerShell 7.2 or later.

```powershell
$ErrorActionPreference = 'Stop'
$urls = terraform output -json app_urls | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $urls.web) { throw 'Could not read the Store Web URL.' }
$backend = "$($urls.web)/backend"
$orderId = [guid](Read-Host 'Succeeded sandbox payment order ID')

$order = Invoke-RestMethod "$backend/orders/$orderId" -TimeoutSec 180
$payment = Invoke-RestMethod "$backend/payments/order/$orderId" -TimeoutSec 180
$expectedMinor = [decimal]$order.totalAmount * 100
# Set to true only if this attempt was created with checkout VAT enabled.
$vatEnabledForAttempt = $false
if ($vatEnabledForAttempt) {
    $expectedMinor += [Math]::Round($expectedMinor * 0.23d, 0, [MidpointRounding]::ToEven)
}
if (-not $order.clientId -or $order.status -ne 'Created' -or
    $payment.status -ne 'succeeded' -or $payment.order_id -ne $orderId.ToString() -or
    $payment.provider_session_id -notlike 'cs_test_*' -or
    $payment.currency -ne 'PLN' -or $payment.amount_minor -ne $expectedMinor) {
    throw 'Expected a Created order and its matching succeeded sandbox payment.'
}

$existingInvoice = Invoke-WebRequest "$backend/invoices/by-order/$orderId" -SkipHttpErrorCheck -TimeoutSec 180
if ($existingInvoice.StatusCode -ne 404) { throw 'Expected no completed invoice for this order.' }
```

Invoice creation requires a client data version in Orders. Store registration
creates the customer and cart. For the selected **demo** customer, preserve an
existing client data version or supply test billing details if the lookup returns
404. This block may create a demo client data version.

```powershell
$clientId = $order.clientId
$clientData = Invoke-WebRequest "$backend/client-data-versions/client/$clientId" -SkipHttpErrorCheck -TimeoutSec 180
if ($clientData.StatusCode -eq 404) {
    $body = @{
        clientName = 'Checkout Demo'
        addressEmail = 'checkout.demo@example.com'
        postalCode = '00-001'
        city = 'Warsaw'
        street = 'Main.Street'
        buildingNumber = '10'
        apartmentNumber = '2'
        phonePrefix = '48'
        phoneNumber = '123456789'
    } | ConvertTo-Json
    $null = Invoke-RestMethod "$backend/client-data-versions/$clientId" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
}
elseif ($clientData.StatusCode -ne 200) {
    throw "Client data lookup failed with HTTP $($clientData.StatusCode)."
}
```

## Deploy the job

Pull the merged configuration and set `payments_fulfillment_enabled = true` at the
top level of your private `terraform.tfvars`. Keep your current image map,
subscription, backend state, and private inputs from TF/04.

```powershell
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
terraform init '-lockfile=readonly'
if ($LASTEXITCODE -ne 0) { throw 'Terraform init failed.' }
terraform plan '-input=false' '-out=tf05.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'TF/05 plan failed.' }
terraform show '-no-color' tf05.tfplan
```

Expect **1 to add, 0 to change, 0 to destroy**, with only
`azurerm_container_app_job.payments_fulfillment[0]` added. The saved plan and remote
state contain credentials. Apply the reviewed file.

```powershell
terraform apply 'tf05.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'TF/05 apply failed.' }

$group = terraform output -raw resource_group_name
if ($LASTEXITCODE -ne 0 -or -not $group) { throw 'Could not read the resource group.' }
$job = terraform output -raw payments_fulfillment_job_name
if ($LASTEXITCODE -ne 0 -or -not $job) { throw 'Could not read the fulfillment job name.' }

az containerapp job execution list -g $group -n $job --query '[].{name:name,status:properties.status,start:properties.startTime}' -o table
```

## Verify fulfillment and replay

Wait for a scheduled execution, or start one on demand with the same job
template. The five-minute schedule can overlap with an on-demand run. The worker
uses fenced leases to coordinate processing. See [Azure job executions](https://learn.microsoft.com/en-us/azure/container-apps/jobs#start-a-job-execution-on-demand).

```powershell
$execution = az containerapp job start -g $group -n $job --query name -o tsv
if ($LASTEXITCODE -ne 0 -or -not $execution) { throw 'Could not start the fulfillment job.' }

az containerapp job execution show -g $group -n $job --job-execution-name $execution --query properties.status -o tsv
```

Repeat the status command until the execution completes. A successful execution
can leave work scheduled for retry. Verify the order and invoice themselves.
This block downloads the completed demo PDF to your temporary directory.

```powershell
$fulfilledOrder = Invoke-RestMethod "$backend/orders/$orderId" -TimeoutSec 180
$invoiceUrl = "$backend/invoices/by-order/$orderId"
$invoice = Invoke-RestMethod $invoiceUrl -TimeoutSec 180
if ($fulfilledOrder.status -ne 'Paid' -or -not $invoice.id -or $invoice.orderId -ne $orderId.ToString()) {
    throw 'Expected the order to be Paid and to have a completed invoice.'
}

$pdfPath = Join-Path ([IO.Path]::GetTempPath()) "invoice-$($invoice.id).pdf"
$pdf = Invoke-WebRequest "$backend/invoices/$($invoice.id)/pdf" -OutFile $pdfPath -PassThru -TimeoutSec 180
if ([string]$pdf.Headers['Content-Type'] -notlike 'application/pdf*' -or (Get-Item $pdfPath).Length -eq 0) {
    throw 'Invoice PDF was missing or invalid.'
}
$invoice | Select-Object id, orderId, createdAt
Start-Process $pdfPath
```

Resend the same successful Stripe event to the same sandbox webhook. Confirm
HTTP 200, run the job again, and verify after that execution finishes.

```powershell
$replayedInvoice = Invoke-RestMethod $invoiceUrl -TimeoutSec 180
$replayedPayment = Invoke-RestMethod "$backend/payments/order/$orderId" -TimeoutSec 180
if ($replayedInvoice.id -ne $invoice.id -or $replayedInvoice.createdAt -ne $invoice.createdAt -or
    $replayedPayment.id -ne $payment.id -or $replayedPayment.status -ne 'succeeded' -or
    $replayedPayment.updated_at -ne $payment.updated_at) {
    throw 'Expected the same completed invoice and payment after replay.'
}
terraform plan '-input=false' '-detailed-exitcode'
if ($LASTEXITCODE -ne 0) { throw 'Expected a successful no-change plan.' }
```

## Verify retry recovery and pause the schedule

For a separate retry drill, use a fresh sandbox payment on a demo order that has
no client data version. Let an execution finish, then verify the order is Paid
and the invoice lookup still returns 404. Add the client data version for that
order as above and let a later scheduled execution process the retry when due.
Verify the same payment and order now have one completed invoice and a PDF.
Check execution history and the worker's
[inspect and resume instructions](https://github.com/MichalBoczula/ECommerceStorePayments/blob/a250dfe1c8752faebd88f9504367eff91dae699e/docs/payment-fulfillment.md#inspect-and-resume)
for unfinished work. If attempts are exhausted, correct the underlying problem
before resuming the failed receipt. Keep order, invoice and execution IDs as
hosted evidence.

Set `payments_fulfillment_enabled = false` when the scheduled demo is off.
Review a new plan and expect deletion of only the job. The payment, receipt,
order and invoice records are stored by the existing services and are available
when the job is enabled again.
