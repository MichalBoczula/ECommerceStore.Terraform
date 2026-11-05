#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $root 'scripts/Test-PortfolioDeployment.ps1'
$catalog = Get-Content -LiteralPath (Join-Path $root 'releases/portfolio.json') -Raw | ConvertFrom-Json -AsHashtable
$searchAddress = 'azurerm_search_service.knowledge[0]'
$fixtureGroup = 'rg-ecommercestore-fixture'
$fixtureSubscription = '00000000-0000-0000-0000-000000000001'
$planFile = New-TemporaryFile
$fixture = @{}

function New-PlanFixture {
    $fixture.revisions = @{}
    $fixture.search = @{ sku = 'free'; state = 'Succeeded' }
    $resources = foreach ($app in $catalog.profiles['store-pact-search'].applications) {
        $name = "ca-$app-fixture"
        $container = @{ name = $app.Replace('_', '-'); image = $catalog.applications[$app].imageReference }
        $fixture.revisions[$name] = @(@{ name = "$name--0001"; weight = 100; containers = @($container.Clone()) })
        @{
            address = 'azurerm_container_app.app["{0}"]' -f $app
            values = @{ name = $name; resource_group_name = $fixtureGroup; template = @(@{ container = @($container) }) }
        }
    }
    $resources += @{ address = $searchAddress; values = @{ name = 'search-fixture'; resource_group_name = $fixtureGroup; sku = 'free' } }
    $fixture.plan = @{
        format_version = '1.2'
        complete = $true
        errored = $false
        variables = @{ subscription_id = @{ value = $fixtureSubscription }; mongo_admin_password = @{ value = 'PRIVATE-FIXTURE' } }
        planned_values = @{ root_module = @{ resources = $resources } }
        resource_changes = @(
            @{ address = 'azurerm_container_app.app["web"]'; mode = 'managed'; change = @{ actions = @('update') } }
            @{ address = $searchAddress; mode = 'managed'; change = @{ actions = @('create') } }
        )
    }
}

function terraform {
    if ((($args | Select-Object -First 2) -join ' ') -ne 'show -json') {
        throw 'Unexpected Terraform invocation in fixture.'
    }
    $global:LASTEXITCODE = 0
    ConvertTo-Json -InputObject $fixture.plan -Depth 40 -Compress
}

function az {
    if ($args[([array]::IndexOf($args, '--subscription') + 1)] -ne $fixtureSubscription) {
        throw 'Azure query must use the subscription from the plan.'
    }
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'search') {
        ConvertTo-Json -InputObject $fixture.search -Compress
        return
    }
    $name = $args[([array]::IndexOf($args, '--name') + 1)]
    ConvertTo-Json -InputObject $fixture.revisions[$name] -Depth 10 -Compress
}

function Assert-Rejected([scriptblock] $Check, [string] $Expected) {
    try {
        $null = & $Check
    }
    catch {
        if ($_.Exception.Message -like $Expected) {
            return
        }
        throw
    }
    throw "Expected rejection matching '$Expected'."
}

try {
    New-PlanFixture
    $summary = & $verifier -PlanFile $planFile.FullName
    if (($summary -join ' ') -match 'PRIVATE-FIXTURE' -or $summary[-1] -ne 'Plan scope and selected images passed.') {
        throw 'The plan summary must show success and omit private inputs.'
    }
    $summary = & $verifier -PlanFile $planFile.FullName -Live
    if ($summary[-1] -ne 'Active Azure revisions and Search passed.') {
        throw 'Expected all live revision and Search checks to pass.'
    }

    $fixture.plan.resource_changes[0].change.actions = @('delete', 'create')
    Assert-Rejected { & $verifier -PlanFile $planFile.FullName } "*delete,create*"

    New-PlanFixture
    $fixture.plan.resource_changes[0].address = 'azurerm_mongo_cluster.users'
    Assert-Rejected { & $verifier -PlanFile $planFile.FullName } "*unexpected plan action*azurerm_mongo_cluster.users*"

    New-PlanFixture
    $web = $fixture.plan.planned_values.root_module.resources | Where-Object { $_.address -eq 'azurerm_container_app.app["web"]' }
    $web.values.template[0].container[0].image = 'example.invalid/older:fixture'
    Assert-Rejected { & $verifier -PlanFile $planFile.FullName } "*selected image for web*"

    New-PlanFixture
    $fixture.revisions['ca-web-fixture'][0].containers[0].image = 'example.invalid/older:fixture'
    Assert-Rejected { & $verifier -PlanFile $planFile.FullName -Live } "*serving revision*has a different container or image*"

    New-PlanFixture
    $fixture.revisions['ca-web-fixture'][0].weight = 80
    Assert-Rejected { & $verifier -PlanFile $planFile.FullName -Live } "*serving 100% of traffic*"

    New-PlanFixture
    $fixture.search.sku = 'basic'
    Assert-Rejected { & $verifier -PlanFile $planFile.FullName -Live } "*provisioned successfully on Free*"

    New-PlanFixture
    $fixture.plan.planned_values.root_module.resources = @($fixture.plan.planned_values.root_module.resources | Where-Object { $_.address -ne $searchAddress })
    $fixture.plan.resource_changes = @($fixture.plan.resource_changes | Where-Object { $_.address -ne $searchAddress })
    $null = & $verifier -PlanFile $planFile.FullName -Profile store-pact -Live
    Assert-Rejected { & $verifier -PlanFile $planFile.FullName } "*requires a planned Free Azure AI Search service*"

    Write-Output 'Deployment verifier fixtures passed.'
}
finally {
    Remove-Item -LiteralPath $planFile.FullName
}
