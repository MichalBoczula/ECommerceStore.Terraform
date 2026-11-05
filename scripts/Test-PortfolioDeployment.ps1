#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PlanFile,

    [ValidateSet('store-pact-search', 'store-pact')]
    [string] $Profile = 'store-pact-search',

    [switch] $Live
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-CliJson([string] $Program, [string[]] $Arguments) {
    # Plan JSON can contain credentials. Keep the raw output in memory and use
    # fixed diagnostics so a parse failure cannot echo a secret into the console.
    $output = & $Program @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "$Program $($Arguments[0]) failed with exit code $LASTEXITCODE."
    }
    try {
        ConvertFrom-Json -InputObject ($output -join [Environment]::NewLine) -AsHashtable -Depth 100 -NoEnumerate
    }
    catch {
        throw "$Program $($Arguments[0]) returned invalid JSON."
    }
}

$planPath = (Resolve-Path -LiteralPath $PlanFile).Path
$root = Split-Path -Parent $PSScriptRoot
$inventory = Get-Content -LiteralPath (Join-Path $root 'releases/portfolio.json') -Raw | ConvertFrom-Json -AsHashtable
$selection = $inventory.profiles[$Profile]

Push-Location -LiteralPath $root
try {
    $plan = Invoke-CliJson 'terraform' @('show', '-json', $planPath)
}
finally {
    Pop-Location
}

if ($plan.format_version -notmatch '^1\.' -or $plan.errored -ne $false -or $plan.complete -ne $true) {
    throw 'Use a complete saved Terraform plan for the existing root.'
}

$resources = @{}
foreach ($resource in $plan.planned_values.root_module.resources) {
    $resources[$resource.address] = $resource.values
}

$apps = foreach ($key in $selection.applications) {
    $address = 'azurerm_container_app.app["{0}"]' -f $key
    $resource = $resources[$address]
    $image = $inventory.applications[$key].imageReference
    $containers = @($resource.template | ForEach-Object { $_.container })
    if ($containers.Count -ne 1 -or $containers[0].image -cne $image -or -not $resource.name) {
        throw "The saved plan must deploy the selected image for $key."
    }

    [pscustomobject]@{
        Key = $key
        Address = $address
        Name = $resource.name
        Group = $resource.resource_group_name
        Container = $containers[0].name
        Image = $image
    }
}

$searchAddress = 'azurerm_search_service.knowledge[0]'
$search = $resources[$searchAddress]
$allowedAddresses = @($apps | ForEach-Object { $_.Address })
if ($selection.terraformSettings.knowledge_search_enabled) {
    if ($search.sku -ne 'free' -or -not $search.name) {
        throw 'This profile requires a planned Free Azure AI Search service.'
    }
    $allowedAddresses += $searchAddress
}

$changes = @{}
foreach ($resourceChange in $plan.resource_changes) {
    if ($resourceChange.mode -ne 'managed') {
        continue
    }

    $address = $resourceChange.address
    $action = $resourceChange.change.actions -join ','
    if ($resourceChange.previous_address -or $null -ne $resourceChange.change.importing) {
        throw "Review the resource move or import separately for $address."
    }
    if ($action -eq 'no-op') {
        continue
    }
    if ($action -notin @('create', 'update') -or $address -notin $allowedAddresses) {
        throw "Review the unexpected plan action '$action' for $address."
    }
    $changes[$address] = $resourceChange.change
}

Write-Output "Release $($inventory.releaseId), profile $Profile"
if (-not $Live) {
    foreach ($app in $apps) {
        $change = $changes[$app.Address]
        if ($change) {
            $previous = if ($change.before) { $change.before.template[0].container[0].image } else { '(new)' }
            Write-Output "$($app.Key) $($change.actions[0])"
            Write-Output "  Refreshed template: $previous"
            Write-Output "  Planned image:      $($app.Image)"
        }
        else {
            Write-Output "$($app.Key) no-op $($app.Image)"
        }
    }
    if ($changes.ContainsKey($searchAddress)) {
        Write-Output "Search $($changes[$searchAddress].actions[0]) $($search.name) (Free)"
    }
    Write-Output 'Plan scope and selected images passed.'
    return
}

$subscription = $plan.variables.subscription_id.value
$subscriptionGuid = [guid]::Empty
if (-not [guid]::TryParse($subscription, [ref] $subscriptionGuid)) {
    throw 'The plan must contain the Azure subscription ID.'
}

foreach ($app in $apps) {
    $revisions = Invoke-CliJson 'az' @(
        'containerapp', 'revision', 'list', '--name', $app.Name,
        '--resource-group', $app.Group, '--subscription', $subscription,
        '--query', '[?properties.active].{name:name,weight:properties.trafficWeight,containers:properties.template.containers[].{name:name,image:image}}',
        '--output', 'json', '--only-show-errors'
    )
    $serving = @($revisions | Where-Object { $_.weight -gt 0 })
    if ($serving.Count -ne 1 -or $serving[0].weight -ne 100) {
        throw "$($app.Key) must have one active revision serving 100% of traffic."
    }
    $containers = @($serving[0].containers)
    if ($containers.Count -ne 1 -or $containers[0].name -cne $app.Container -or $containers[0].image -cne $app.Image) {
        throw "$($app.Key) serving revision $($serving[0].name) has a different container or image. Expected $($app.Image)."
    }
    Write-Output "$($app.Key) $($serving[0].name) $($app.Image)"
}

if ($search) {
    $service = Invoke-CliJson 'az' @(
        'search', 'service', 'show', '--name', $search.name,
        '--resource-group', $search.resource_group_name, '--subscription', $subscription,
        '--query', '{sku:sku.name,state:provisioningState}', '--output', 'json', '--only-show-errors'
    )
    if ($service.sku -ne 'free' -or $service.state -ne 'Succeeded') {
        throw "Search service $($search.name) must be provisioned successfully on Free."
    }
    Write-Output "Search $($search.name) Free Succeeded"
}

Write-Output 'Active Azure revisions and Search passed.'
