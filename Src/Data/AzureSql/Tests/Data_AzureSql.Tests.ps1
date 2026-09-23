using module ../../../../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationManifest = Join-Path $PSScriptRoot '../../../../../SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1'
$adapterManifest = Join-Path $PSScriptRoot '../PowerShell/Data_AzureSql.psd1'
Import-Module (Resolve-Path $foundationManifest).ProviderPath -Force
Import-Module (Resolve-Path $adapterManifest).ProviderPath -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$adapter = Resolve-Data_AzureSql
$jacket = [PSCustomObject]@{
    Name = 'SDAFusionDatabase'
    VirtualPath = 'SovereignTrust.Adapters.Data.AzureSql.FusionDatabase.Persistent.Full'
    Resource = 'synthetic-test-resource'
}
$construct = $adapter.Construct($jacket)
Assert-True (-not $construct.Failure() -and $adapter.Configuration -eq $jacket) 'Construct did not retain the hydrated jacket.'
Assert-True ($adapter.Signal.GetJacket().GetResult() -eq $jacket) 'Adapter signal lost the jacket.'

$conduction = [Signal]::Start('AzureSqlTest.Conduction') | Select-Object -Last 1
$item = [Signal]::Start('AzureSqlTest.Item') | Select-Object -Last 1
$queryPlan = [PSCustomObject]@{ Config = [PSCustomObject]@{ CommandText = 'select 1'; Parameters = @{ '@Id' = 1 }; CommandTimeoutSeconds = 15 } }
$queryBefore = $queryPlan | ConvertTo-Json -Depth 100 -Compress

$unsupported = $adapter.Invoke('FusionDatabase', 'Other', $conduction, $queryPlan, $item)
Assert-True ($unsupported.Failure()) 'Unsupported activity should return a failed signal.'
$missingConfig = $adapter.Invoke('FusionDatabase', 'Query', $conduction, [PSCustomObject]@{}, $item)
Assert-True ($missingConfig.Failure()) 'Missing Config should return a failed signal.'
$missingCommand = $adapter.Invoke('FusionDatabase', 'Query', $conduction, [PSCustomObject]@{ Config = @{} }, $item)
Assert-True ($missingCommand.Failure()) 'Missing CommandText should return a failed signal.'
$missingProcedure = $adapter.Invoke('FusionDatabase', 'Write', $conduction, [PSCustomObject]@{ Config = @{} }, $item)
Assert-True ($missingProcedure.Failure()) 'Missing Procedure should return a failed signal.'
$missingDeleteCommand = $adapter.Invoke('FusionDatabase', 'Delete', $conduction, [PSCustomObject]@{ Config = @{} }, $item)
Assert-True ($missingDeleteCommand.Failure()) 'Delete without CommandText should return a failed signal.'
$pending = $adapter.Invoke('FusionDatabase', 'Query', $conduction, $queryPlan, $item)
Assert-True ($pending.Failure()) 'Unimplemented SQL execution should return a failed signal.'
Assert-True (($queryPlan | ConvertTo-Json -Depth 100 -Compress) -eq $queryBefore) 'Invocation changed the caller plan.'

$emptyTable = [System.Data.DataTable]::new('EmptyRecords')
$null = $emptyTable.Columns.Add('Id', [int])
$binaryTable = [System.Data.DataTable]::new('Values')
$null = $binaryTable.Columns.Add('Payload', [byte[]])
$null = $binaryTable.Columns.Add('Amount', [decimal])
$null = $binaryTable.Columns.Add('Missing', [string])
$null = $binaryTable.Columns.Add('When', [datetime])
$null = $binaryTable.Columns.Add('LargeId', [long])
$utcDate = [datetime]::SpecifyKind([datetime]'2024-12-01T12:34:56', [DateTimeKind]::Utc)
$null = $binaryTable.Rows.Add([byte[]](1, 2, 3), [decimal]'123.4500', [DBNull]::Value, $utcDate, [long]9007199254740992)
$dataSet = [System.Data.DataSet]::new()
$null = $dataSet.Tables.Add($emptyTable)
$null = $dataSet.Tables.Add($binaryTable)
$json = ConvertTo-AzureSqlJsonResult -Operation Query -Value $dataSet
$result = $json | ConvertFrom-Json -Depth 100
Assert-True ($result.ResultSets.Count -eq 2) 'Multiple result sets were not preserved.'
Assert-True ($result.ResultSets[0].Rows.Count -eq 0 -and $result.ResultSets[0].Columns[0].Name -eq 'Id') 'Empty result-set metadata was lost.'
Assert-True ($result.ResultSets[1].Rows[0].Payload -eq 'AQID') 'Binary value was not base64 encoded.'
Assert-True ($result.ResultSets[1].Rows[0].Amount -is [string] -and [decimal]$result.ResultSets[1].Rows[0].Amount -eq [decimal]'123.4500') 'Decimal precision was not preserved.'
Assert-True ($null -eq $result.ResultSets[1].Rows[0].Missing) 'DBNull was not serialized as null.'
Assert-True ($result.ResultSets[1].Rows[0].When.ToUniversalTime().ToString('o') -eq '2024-12-01T12:34:56.0000000Z') 'Date was not serialized as UTC ISO 8601.'
Assert-True ($result.ResultSets[1].Rows[0].LargeId -is [string] -and $result.ResultSets[1].Rows[0].LargeId -eq '9007199254740992') 'Large integer was not serialized as text.'
Assert-True ($json -notmatch 'DataSet|DataTable|DataRow') 'A database-specific type escaped in JSON.'

Write-Output 'PASS: AzureSql construction, failed-signal validation, immutable plan, and JSON conversion contracts.'
