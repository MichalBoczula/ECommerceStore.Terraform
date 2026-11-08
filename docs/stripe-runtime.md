# TF/04 Stripe sandbox rollout

Complete the [TF/03 hosted checks](initial-deployment.md) first. Use the same
Terraform checkout, Azure subscription, backend state and image map. This step
updates the existing Payments Container App. The selected Store Web image returns
to the Orders screen and can reopen the order when Checkout started in the same
browser tab. Payments confirms the payment from Stripe's signed webhook.

## Set up the webhook and plan

1. Read the deployed URLs in PowerShell 7.2 or later.

   ```powershell
   $urls = terraform output -json app_urls | ConvertFrom-Json
   if ($LASTEXITCODE -ne 0 -or -not $urls.payments -or -not $urls.web) {
       throw 'Verify the TF/03 Payments and Web deployment first.'
   }
   "$($urls.payments)/payments/webhooks/stripe"
   ```

2. In the [Stripe Dashboard](https://dashboard.stripe.com/sandboxes), select your
   sandbox and register that Payments HTTPS URL in Workbench. Use **Your account**,
   snapshot events and API version `2026-08-26.dahlia`, as specified by the
   [selected Payments release](https://github.com/MichalBoczula/ECommerceStorePayments/blob/a250dfe1c8752faebd88f9504367eff91dae699e/docs/stripe-webhooks.md).
   Subscribe to these events.

   - `checkout.session.completed`
   - `checkout.session.async_payment_succeeded`
   - `checkout.session.async_payment_failed`
   - `checkout.session.expired`

3. Add `payments_stripe_enabled = true` to your private Terraform inputs. Load the
   `sk_test_` key from the same sandbox and the `whsec_` secret from this
   Dashboard endpoint into the deployment shell.

   ```powershell
   $env:TF_VAR_payments_stripe_secret_key = Read-Host 'Stripe sandbox API key' -MaskInput
   $env:TF_VAR_payments_stripe_webhook_secret = Read-Host 'Stripe endpoint signing secret' -MaskInput
   ```

   Terraform supplies both values as Payments Container App secrets. Keep the
   shell inputs, saved plan and remote state private. Sensitive inputs redact
   terminal plan output. The saved plan and state contain secret values.
   See [Terraform's sensitive data guide](https://developer.hashicorp.com/terraform/language/manage-sensitive-data).

4. Pull the merged configuration and review a saved plan.

   ```powershell
   git pull --ff-only
   terraform init -lockfile=readonly
   terraform plan -input=false -out=tf04.tfplan
   terraform show -no-color tf04.tfplan
   ```

   Stop on any command failure. With TF/03 settled, expect one in-place Payments
   update and zero additions or destroys. Keep the image pin. The return URLs are
   the deployed Web origin followed by `/orders?checkout=success` and
   `/orders?checkout=cancel`. Apply the reviewed plan.

   ```powershell
   terraform apply tf04.tfplan
   Invoke-RestMethod "$($urls.payments)/health/ready" -TimeoutSec 180
   ```

## Verify hosted checkout

1. In the deployed storefront, create a fresh demo order with a PLN total of at
   least PLN 2. Open its order detail and start Checkout. Check that the Stripe
   sandbox shows the order total and currency. Back out once, confirm the browser
   returns to the same order and that the payment is still `pending`, then resume.
   The same pending attempt should reuse the same Stripe session.
2. Complete the hosted flow with a [Stripe test card](https://docs.stripe.com/testing#cards).
   Confirm the browser returns to the order and the UI shows **Payment confirmed**
   after it reads the webhook-updated state. In Workbench, check that
   `checkout.session.completed` for this session received HTTP 200 from Payments.
3. Read the persisted payment and verify the order and Stripe identifiers.

   ```powershell
   $orderId = [guid](Read-Host 'Completed test order ID')
   $paymentUrl = "$($urls.payments)/payments/order/$orderId"
   $payment = Invoke-RestMethod $paymentUrl -TimeoutSec 180
   $order = Invoke-RestMethod "$($urls.web)/backend/orders/$orderId" -TimeoutSec 180
   if ($payment.status -ne 'succeeded' -or $payment.order_id -ne $orderId.ToString() -or
       $payment.provider_session_id -notlike 'cs_test_*' -or -not $payment.provider_payment_id -or
       $payment.currency -ne 'PLN' -or $payment.amount_minor -ne ([decimal]$order.totalAmount * 100) -or
       $order.status -ne 'Created') {
       throw 'Expected a confirmed sandbox payment with the original amount and a Created order.'
   }
   $payment | Select-Object id, order_id, status, amount_minor, currency, provider_session_id, provider_payment_id
   ```

   Match the session and PaymentIntent IDs to the sandbox event. Resend the same
   event to the same destination, confirm another HTTP 200 and repeat the read.
   The payment ID, status, provider IDs and `updated_at` should match the first
   confirmed read. Order fulfillment and invoice generation are TF/05.

4. Run `terraform plan -input=false -detailed-exitcode` in the same shell with the
   same inputs. Expect exit code 0. Keep the nonsecret revision, order, session
   and event IDs and the result of the replay check as acceptance evidence.

## Enable VAT for new sandbox attempts

Upgrade `app_images.payments` to the published VAT-capable digest and apply it
with `payments_stripe_checkout_vat_enabled = false`. Verify the active Payments
API revision and fulfillment job template both use that digest. Wait for older
executions to finish and confirm an execution using the updated template
completes before enabling VAT. Older worker images cannot fulfill new
VAT-enabled receipts.

Then set `payments_stripe_checkout_vat_enabled = true` in the private inputs,
review a new plan, and apply the Payments API configuration update. Create a
fresh sandbox order. For a 4,998.00 PLN subtotal, verify Stripe charges
6,147.54 PLN, the signed webhook records `amount_minor = 614754`, and the
completed invoice PDF shows the same total. Existing sessions keep their
original amount and existing invoices remain as issued. Keep a VAT-capable
image for both runtimes while any VAT-enabled attempts are outstanding.

## Pause checkout or rotate credentials

Set `payments_stripe_enabled = false` and review and apply a new plan to stop new
sessions. Keep both secret inputs and the sandbox endpoint during that apply. The
new revision keeps accepting signed events for outstanding sessions. It removes
the API key reference from its environment. Remove a secret only after the
revisions referencing it are inactive. Keep the webhook active until outstanding
sessions and pending deliveries are resolved.

After updating a secret alone, restart the active Payments revision or deploy a
new one so that the process reads the new value. Verify readiness and a signed
delivery after a signing-secret rotation. See
[Azure Container Apps secret management](https://learn.microsoft.com/azure/container-apps/manage-secrets).
