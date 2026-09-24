using module SignalGraph

param([switch]$TargetProbe, [switch]$FixtureProbe)

# Run only in a fresh pwsh process. All fixture DML is scoped to this run ID.
$ErrorActionPreference = 'Stop'
if ($TargetProbe -and $FixtureProbe) { throw 'Choose one read-only probe mode.' }
$foundationManifest = Join-Path $PSScriptRoot '../../../../../SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1'
$configPath = Join-Path $PSScriptRoot '../../../../../SDAFusion-Content/SDA/Config/SDAFusionApp.Json'
$moduleRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).ProviderPath
Import-Module (Resolve-Path $foundationManifest).ProviderPath -Force
if (Get-Module Data_AzureSql) { throw 'Live suite must start with AzureSql unloaded.' }

$missing = [System.Collections.Generic.List[string]]::new()
if (-not $TargetProbe -and -not $FixtureProbe) {
    if ($env:SDA_AZURESQL_LIVE_READY -cne '1') { $missing.Add('explicit live-suite opt-in') }
    if ($env:SDA_AZURESQL_LIVE_DEDICATED -cne '1') { $missing.Add('dedicated integration database approval') }
    if ($env:SDA_AZURESQL_LIVE_NETWORK_READY -cne '1') { $missing.Add('network and firewall access') }
    if ($env:SDA_AZURESQL_LIVE_IDENTITY_READY -cne '1') { $missing.Add('authenticated least-privilege identity') }
    if ($env:SDA_AZURESQL_LIVE_FIXTURES_READY -cne '1') { $missing.Add('pre-provisioned, safely resettable fixtures') }
}
if (-not $TargetProbe -and $env:SDA_AZURESQL_LIVE_SCHEMA -cnotmatch '^sda_azure_sql_it_[A-Za-z0-9_]+$') { $missing.Add('dedicated sda_azure_sql_it_* schema name') }
if ([string]::IsNullOrWhiteSpace($env:SDA_AZURESQL_LIVE_SERVER)) { $missing.Add('approved integration server name') }
if ([string]::IsNullOrWhiteSpace($env:SDA_AZURESQL_LIVE_DATABASE)) { $missing.Add('expected integration database name') }
if ($missing.Count -gt 0) {
    $scope = if ($TargetProbe) { 'target probe' } elseif ($FixtureProbe) { 'fixture probe' } else { 'live Azure SQL suite' }
    Write-Output "SKIP: $scope not run; missing prerequisites: $($missing -join ', ')."
    exit 77
}

function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Set-LiveStage([string]$Stage, [string]$Cleanup = $null, [string]$Result = $null) {
    $script:stage = $Stage
    if ($null -eq $script:liveRecord) { return }
    $script:liveRecord.Stage = $Stage
    if ($null -ne $Cleanup) { $script:liveRecord.Cleanup = $Cleanup }
    if ($null -ne $Result) { $script:liveRecord.Result = $Result }
    try { $script:liveRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:recordPath -Encoding utf8 }
    catch { $script:recordWriteFailed = $true }
}
function Get-ArtifactIdentity([string]$Root) {
    $entries = foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        "$relative $((Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash)"
    }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))))
}
function Invoke-LivePlan([string]$Activity, [object]$Config) {
    $plan = [pscustomobject]@{ Adapter = 'Data.FusionDatabase'; Activity = $Activity; Config = $Config }
    $item = [Signal]::Start('AzureSqlLive.Item') | Select-Object -Last 1
    $item.SetPointer($script:conductor.Signal.GetPointer()) | Out-Null
    $signal = Invoke-MappedAdapter -Adapter $plan.Adapter -Activity $Activity -Signal $script:runSignal -Plan $plan -ItemSignal $item | Select-Object -Last 1
    Assert (-not $signal.Failure() -and $signal.HasResult()) "$Activity returned a failed signal."
    $json = $signal.GetResult()
    Assert ($json -is [string]) "$Activity did not return JSON text."
    $envelope = $json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    Assert ($envelope.Operation -ceq $Activity -and $null -ne $envelope.ResultSets -and $null -ne $envelope.OutputParameters) "$Activity returned an invalid envelope."
    Assert ($json -notmatch 'Microsoft\.Data\.SqlClient|System\.Data\.Data(Table|Row|Set)') "$Activity leaked provider objects."
    return $envelope
}

$script:stage = 'configuration'
$script:liveRecord = $null
$script:recordPath = $null
$script:recordWriteFailed = $false
try {
    Set-LiveStage 'configuration'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -Depth 100
    $agent = @($config.Agents | Where-Object Name -eq 'sdadev01')[0]
    $role = $agent.Roles.SDAWorkItems
    $sqlJacket = @($role.Adapters | Where-Object Name -eq 'SDAFusionDatabase')[0]
    $secretJacket = @($role.Adapters | Where-Object { $_.VirtualPath -ceq 'SovereignTrust.Adapters.Storage.AzureKeyVault.Secrets.Persistent.Read' -and $_.Name -ceq 'SDASecrets' })[0]
    Assert ($null -ne $sqlJacket -and $null -ne $secretJacket) 'Production configuration lacks SQL or Secrets jacket.'
    Assert ($sqlJacket.Resource -ceq '[Storage.Secrets.Read.sdafusion-sqldatabase|]') 'SQL jacket resource expression differs from the production contract.'

    Set-LiveStage 'foundation-bootstrap'
    $bootstrap = [Signal]::Start('AzureSqlLive.Bootstrap') | Select-Object -Last 1
    $bootstrap.SetResult([pscustomobject]@{}) | Out-Null
    $conductorSignal = New-Conductor -HostConductor $null -ConductionSignal $bootstrap | Select-Object -Last 1
    Assert (-not $conductorSignal.Failure() -and $conductorSignal.HasResult()) 'Conductor bootstrap failed.'
    $script:conductor = $conductorSignal.GetResult()
    $conductorJacket = [Signal]::Start('AzureSqlLive.Conductor') | Select-Object -Last 1
    $conductorJacket.SetJacket($conductor.Signal) | Out-Null
    $conductorJacket.SetPointer($conductor.Signal.GetPointer()) | Out-Null
    $script:runSignal = [Signal]::Start('AzureSqlLive.Run') | Select-Object -Last 1
    $runSignal.SetJacket($conductor.Signal) | Out-Null
    $runSignal.SetPointer($conductor.Signal.GetPointer()) | Out-Null
    $runSignal.SetControl($conductorJacket) | Out-Null

    $rootAdapter = & (Get-Module SovereignTrust.Foundation) { [Storage_EmbeddedFileSystem]::new() }
    $rootJacket = [pscustomobject]@{ Name = 'Modules'; VirtualPath = 'SovereignTrust.Adapters.Storage.EmbeddedFileSystem.ModuleRoots.Persistent.Read'; Addresses = @($moduleRoot) }
    $rootAdapter.Construct($rootJacket) | Out-Null
    $rootRegistration = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $runSignal -ConductionContext $runSignal -Adapter $rootAdapter | Select-Object -Last 1
    Assert (-not $rootRegistration.Failure()) 'ModuleRoots bootstrap failed.'

    Set-LiveStage 'secrets-bootstrap'
    $secretSignal = [Signal]::Start('AzureSqlLive.SecretsJacket') | Select-Object -Last 1
    $secretSignal.SetResult($secretJacket) | Out-Null
    $secretResolution = & (Get-Module SovereignTrust.Foundation) {
        param($signal, $jacket)
        Resolve-AdapterFromJacket -Signal $signal -ConductionContext $signal -Jacket $jacket | Select-Object -Last 1
    } $runSignal $secretSignal
    Assert (-not $secretResolution.Failure() -and $secretResolution.HasResult()) 'Secrets bootstrap resolution failed.'
    $secretRegistration = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $runSignal -ConductionContext $runSignal -Adapter $secretResolution.GetResult() | Select-Object -Last 1
    Assert (-not $secretRegistration.Failure()) 'Secrets bootstrap registration failed.'

    Set-LiveStage 'lazy-registration'
    $global:AzureSqlLiveFactoryCalls = 0
    & (Get-Module SovereignTrust.Foundation) {
        $script:AzureSqlLiveOriginalResolveModuleFromAdapter = (Get-Command Resolve-ModuleFromAdapter).ScriptBlock
        Set-Item Function:script:Resolve-ModuleFromAdapter -Value {
            param([Signal]$Signal, [string]$Slot, [string]$ModuleName, [string]$RelativePath)
            $resolved = & $script:AzureSqlLiveOriginalResolveModuleFromAdapter -Signal $Signal -Slot $Slot -ModuleName $ModuleName -RelativePath $RelativePath | Select-Object -Last 1
            if (-not $resolved.Failure() -and $ModuleName -ceq 'Data_AzureSql.psd1') {
                Set-Item Function:script:Resolve-Data_AzureSql -Value {
                    $global:AzureSqlLiveFactoryCalls++
                    return & (Get-Module Data_AzureSql) { Resolve-Data_AzureSql }
                }
            }
            return $resolved
        }
    }
    $sqlSignal = [Signal]::Start('AzureSqlLive.SqlJacket') | Select-Object -Last 1
    $sqlSignal.SetResult($sqlJacket) | Out-Null
    $loaderItem = [Signal]::Start('AzureSqlLive.LoaderItem') | Select-Object -Last 1
    $loaderItem.SetJacket($sqlSignal) | Out-Null
    $fab = & (Get-Module SovereignTrust.Foundation) { [FabCondenser]::new() }
    $registrationSignal = $fab.Invoke('Fab', 'Invoke', $runSignal, $null, $loaderItem) | Select-Object -Last 1
    Assert (-not $registrationSignal.Failure() -and -not (Get-Module Data_AzureSql)) 'AzureSql loaded before first mapped invocation.'
    $registration = $registrationSignal.GetResult()

    $schema = $env:SDA_AZURESQL_LIVE_SCHEMA
    $table = "[$schema].[AzureSqlAdapterFixture]"
    $procedure = "[$schema].[usp_IngestAzureSqlAdapterFixture]"
    $runId = [guid]::NewGuid()
    $artifactRoot = (Resolve-Path (Join-Path $PSScriptRoot '../PowerShell')).ProviderPath
    $artifactHash = Get-ArtifactIdentity $artifactRoot
    $recordsRoot = Join-Path ([IO.Path]::GetTempPath()) 'SovereignTrust.AzureSql.LiveRuns'
    New-Item -ItemType Directory -Path $recordsRoot -Force | Out-Null
    $script:recordPath = Join-Path $recordsRoot "$runId.json"
    $script:liveRecord = [ordered]@{
        RunId = $runId.ToString()
        ArtifactSha256 = $artifactHash
        ConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash
        Runtime = $PSVersionTable.PSVersion.ToString()
        Stage = 'target-validation'
        FailedStage = $null
        FailureClass = $null
        Cleanup = 'NotStarted'
        Result = 'Running'
    }
    Set-LiveStage 'target-validation'
    Assert (-not $script:recordWriteFailed -and (Test-Path -LiteralPath $recordPath -PathType Leaf)) 'Could not persist the recovery record before live operations.'
    Write-Output "LIVE_RUN_ID=$runId"
    Write-Output "ARTIFACT_SHA256=$artifactHash"
    Write-Output "RECOVERY_RECORD=$recordPath"
    $runParameter = @(@{ Name = '@RunId'; SqlDbType = 'UniqueIdentifier'; Value = $runId })
    $identity = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = 'SELECT DB_NAME() AS DatabaseName'; Parameters = @() })
    Assert ($identity.ResultSets[0].Rows[0].DatabaseName -ceq $env:SDA_AZURESQL_LIVE_DATABASE) 'Connected database did not match the approved resource.'
    Assert ($registration.State -eq 'Resolved' -and $registration.Instance.GetType().Name -ceq 'Data_AzureSql') 'Production lazy resolution did not construct Data_AzureSql.'
    Assert ($global:AzureSqlLiveFactoryCalls -eq 1) 'Production lazy resolution did not invoke Resolve-Data_AzureSql once.'
    $loadedModule = & (Get-Module SovereignTrust.Foundation) { Get-Module Data_AzureSql }
    Assert ($null -ne $loadedModule) 'Production resolver did not import AzureSql.'
    $builder = & $loadedModule { param($adapter) New-AzureSqlConnectionBuilder -Adapter $adapter } $registration.Instance
    Assert ($builder.DataSource -ieq $env:SDA_AZURESQL_LIVE_SERVER -and $builder.InitialCatalog -ieq $env:SDA_AZURESQL_LIVE_DATABASE) 'Protected resource does not target the approved integration server and database.'
    $builder = $null
    if ($TargetProbe) {
        Set-LiveStage 'complete' -Result 'Passed'
        Write-Output 'PASS: production hydration and lazy resolution reached the approved server and database with authenticated read-only SqlClient execution.'
        exit 0
    }
    Set-LiveStage 'fixture-validation'
    $schemaCheck = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = 'SELECT SCHEMA_ID(@SchemaName) AS SchemaId'; Parameters = @(@{ Name = '@SchemaName'; SqlDbType = 'NVarChar'; Size = 128; Value = $schema }) })
    Assert ($null -ne $schemaCheck.ResultSets[0].Rows[0].SchemaId) 'Dedicated integration schema is unavailable.'
    $fixture = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = 'SELECT OBJECT_ID(@TableName, ''U'') AS TableId, OBJECT_ID(@ProcedureName, ''P'') AS ProcedureId'; Parameters = @(
        @{ Name = '@TableName'; SqlDbType = 'NVarChar'; Size = 256; Value = "${schema}.AzureSqlAdapterFixture" },
        @{ Name = '@ProcedureName'; SqlDbType = 'NVarChar'; Size = 256; Value = "${schema}.usp_IngestAzureSqlAdapterFixture" }
    ) })
    Assert ($null -ne $fixture.ResultSets[0].Rows[0].TableId -and $null -ne $fixture.ResultSets[0].Rows[0].ProcedureId) 'Dedicated table and procedure are unavailable.'
    $preflight = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = @'
SELECT
    (SELECT COUNT(*) FROM sys.columns c JOIN sys.types t ON c.user_type_id=t.user_type_id
       WHERE c.object_id=OBJECT_ID(@TableName,'U') AND
       ((c.name='RunId' AND t.name='uniqueidentifier' AND c.is_nullable=0) OR
        (c.name='Id' AND t.name='int') OR
        (c.name='Name' AND t.name='nvarchar') OR
        (c.name='Kind' AND t.name='nvarchar' AND c.is_nullable=0) OR
        (c.name='Document' AND t.name='nvarchar'))) AS MatchingColumns,
    (SELECT COUNT(*) FROM sys.parameters p JOIN sys.types t ON p.user_type_id=t.user_type_id
       WHERE p.object_id=OBJECT_ID(@ProcedureName,'P') AND
       ((p.name='@Payload' AND t.name='nvarchar' AND p.max_length=-1) OR
        (p.name='@RunId' AND t.name='uniqueidentifier') OR
        (p.name='@Kind' AND t.name='nvarchar'))) AS MatchingParameters,
    (SELECT COUNT(*) FROM sys.triggers WHERE parent_id=OBJECT_ID(@TableName,'U')) AS TriggerCount,
    (SELECT COUNT(*) FROM sys.sql_expression_dependencies
       WHERE referencing_id=OBJECT_ID(@ProcedureName,'P') AND
             (referenced_id IS NULL OR referenced_id<>OBJECT_ID(@TableName,'U'))) AS ExternalDependencies,
    OBJECT_DEFINITION(OBJECT_ID(@ProcedureName,'P')) AS ProcedureDefinition,
    HAS_PERMS_BY_NAME(@TableName,'OBJECT','SELECT') AS CanSelect,
    HAS_PERMS_BY_NAME(@TableName,'OBJECT','DELETE') AS CanDelete,
    HAS_PERMS_BY_NAME(@ProcedureName,'OBJECT','EXECUTE') AS CanExecute,
    HAS_PERMS_BY_NAME(@TableName,'OBJECT','ALTER') AS CanAlterFixture,
    IS_ROLEMEMBER('db_owner') AS IsDbOwner,
    IS_ROLEMEMBER('db_datawriter') AS IsDbDataWriter,
    IS_ROLEMEMBER('db_ddladmin') AS IsDbDdlAdmin,
    (SELECT COUNT(*) FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id
       WHERE t.object_id<>OBJECT_ID(@TableName,'U') AND
          (HAS_PERMS_BY_NAME(QUOTENAME(s.name)+'.'+QUOTENAME(t.name),'OBJECT','INSERT')=1 OR
           HAS_PERMS_BY_NAME(QUOTENAME(s.name)+'.'+QUOTENAME(t.name),'OBJECT','UPDATE')=1 OR
           HAS_PERMS_BY_NAME(QUOTENAME(s.name)+'.'+QUOTENAME(t.name),'OBJECT','DELETE')=1)) AS OtherWritableTables
'@; Parameters = @(
        @{ Name = '@TableName'; SqlDbType = 'NVarChar'; Size = 256; Value = "${schema}.AzureSqlAdapterFixture" },
        @{ Name = '@ProcedureName'; SqlDbType = 'NVarChar'; Size = 256; Value = "${schema}.usp_IngestAzureSqlAdapterFixture" }
    ) })
    $contract = $preflight.ResultSets[0].Rows[0]
    Assert ($contract.MatchingColumns -eq 5 -and $contract.MatchingParameters -eq 3 -and
        $contract.TriggerCount -eq 0 -and $contract.ExternalDependencies -eq 0) 'Fixture shape, triggers, or procedure dependencies violate the dedicated contract.'
    Assert ($contract.CanSelect -eq 1 -and $contract.CanDelete -eq 1 -and $contract.CanExecute -eq 1 -and
        $contract.CanAlterFixture -ne 1 -and $contract.IsDbOwner -ne 1 -and
        $contract.IsDbDataWriter -ne 1 -and $contract.IsDbDdlAdmin -ne 1 -and
        $contract.OtherWritableTables -eq 0) 'The live identity lacks fixture permissions or has unrelated write privileges.'
    $definition = [string]$contract.ProcedureDefinition
    Assert ($definition -match '(?i)\bOPENJSON\s*\(' -and $definition -match '(?i)\bINSERT\b' -and
        $definition -match '(?i)@RunId\b' -and $definition -match '(?i)@Payload\b' -and
        $definition -notmatch '(?i)\b(EXEC|EXECUTE|UPDATE|DELETE|MERGE|TRUNCATE|DROP)\b') 'Fixture procedure definition requires provisioning-owner review.'
    $definition = $null
    if ($FixtureProbe) {
        Set-LiveStage 'complete' -Result 'Passed'
        Write-Output 'PASS: dedicated fixture shape, dependencies, triggers, and visible least-privilege permissions passed read-only preflight.'
        exit 0
    }

    $scenarioFailure = $null
    $scenarioStage = $null
    $cleanupFailure = $null
    try {
        Set-LiveStage 'json-ingestion'
        $null = Invoke-LivePlan Write ([pscustomobject]@{ Procedure = $procedure; InputFormat = 'Json'; Content = '[{"Id":1,"Name":"Alpha"},{"Id":2,"Name":"Beta"}]'; Parameters = @(
            @{ Name = '@RunId'; SqlDbType = 'UniqueIdentifier'; Value = $runId },
            @{ Name = '@Kind'; SqlDbType = 'NVarChar'; Size = 16; Value = 'Records' }
        ) })
        Set-LiveStage 'csv-ingestion'
        $csv = "Id,Name`r`n3,`"Gallery`r`nArchive`"`r`n4,`"`""
        $null = Invoke-LivePlan Write ([pscustomobject]@{ Procedure = $procedure; InputFormat = 'Csv'; Content = $csv; ColumnSchema = @{ Id = 'int' }; Parameters = @(
            @{ Name = '@RunId'; SqlDbType = 'UniqueIdentifier'; Value = $runId },
            @{ Name = '@Kind'; SqlDbType = 'NVarChar'; Size = 16; Value = 'Records' }
        ) })
        Set-LiveStage 'document-ingestion'
        $null = Invoke-LivePlan Write ([pscustomobject]@{ Procedure = $procedure; InputFormat = 'Object'; PayloadMode = 'Document'; Content = [pscustomobject]@{ Metadata = [pscustomobject]@{ Name = 'WeatherVault'; Version = 1 } }; Parameters = @(
            @{ Name = '@RunId'; SqlDbType = 'UniqueIdentifier'; Value = $runId },
            @{ Name = '@Kind'; SqlDbType = 'NVarChar'; Size = 16; Value = 'Document' }
        ) })

        Set-LiveStage 'multiple-and-empty-results'
        $rows = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = "SELECT Id, Name, Kind, Document FROM $table WHERE RunId = @RunId ORDER BY Id; SELECT Id, Name FROM $table WHERE RunId = @RunId AND Id = -1"; Parameters = $runParameter })
        Assert ($rows.ResultSets.Count -eq 2 -and $rows.ResultSets[0].Rows.Count -eq 5 -and $rows.ResultSets[1].Rows.Count -eq 0 -and $rows.ResultSets[1].Columns.Count -ge 2) 'Multiple or empty result sets did not preserve rows and schema.'
        Assert (@($rows.ResultSets[0].Rows | Where-Object { $_.Id -eq 1 -and $_.Name -ceq 'Alpha' -and $_.Kind -ceq 'Records' }).Count -eq 1 -and
            @($rows.ResultSets[0].Rows | Where-Object { $_.Id -eq 2 -and $_.Name -ceq 'Beta' -and $_.Kind -ceq 'Records' }).Count -eq 1) 'JSON record ingestion did not preserve values.'
        Assert (@($rows.ResultSets[0].Rows | Where-Object { $_.Id -eq 3 -and $_.Name -ceq "Gallery`r`nArchive" }).Count -eq 1) 'CSV quoted newline was not preserved.'
        Assert (@($rows.ResultSets[0].Rows | Where-Object { $_.Id -eq 4 -and $_.Name -ceq '' }).Count -eq 1) 'CSV empty field was not preserved.'
        $documentRow = @($rows.ResultSets[0].Rows | Where-Object Kind -eq 'Document')[0]
        Assert (($documentRow.Document | ConvertFrom-Json -Depth 100).Metadata.Name -ceq 'WeatherVault') 'Nested document was not preserved.'

        Set-LiveStage 'rollback'
        $failedPlan = [pscustomobject]@{ Adapter = 'Data.FusionDatabase'; Activity = 'Delete'; Config = [pscustomobject]@{
            CommandText = "DELETE FROM $table WHERE RunId = @RunId AND Id = 2; THROW 51000, 'expected rollback', 1;"
            Parameters = $runParameter
        } }
        $failureItem = [Signal]::Start('AzureSqlLive.FailureItem') | Select-Object -Last 1
        $failureItem.SetPointer($conductor.Signal.GetPointer()) | Out-Null
        $failure = Invoke-MappedAdapter -Adapter $failedPlan.Adapter -Activity Delete -Signal $runSignal -Plan $failedPlan -ItemSignal $failureItem | Select-Object -Last 1
        Assert ($failure.Failure()) 'Failing mutation did not return a failed signal.'
        $afterRollback = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = "SELECT COUNT(*) AS RecordCount FROM $table WHERE RunId = @RunId"; Parameters = $runParameter })
        Assert ($afterRollback.ResultSets[0].Rows[0].RecordCount -eq 5) 'Failed Delete did not roll back.'

        Set-LiveStage 'delete-and-remaining-records'
        $deleted = Invoke-LivePlan Delete ([pscustomobject]@{ CommandText = "DELETE FROM $table WHERE RunId = @RunId AND Id = 2"; Parameters = $runParameter })
        Assert ($deleted.RowsAffected -eq 1) 'Delete affected count was incorrect.'
        $zero = Invoke-LivePlan Delete ([pscustomobject]@{ CommandText = "DELETE FROM $table WHERE RunId = @RunId AND Id = -1"; Parameters = $runParameter })
        Assert ($zero.RowsAffected -eq 0) 'Delete did not retain zero affected rows.'
        $remaining = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = "SELECT COUNT(*) AS RecordCount FROM $table WHERE RunId = @RunId"; Parameters = $runParameter })
        Assert ($remaining.ResultSets[0].Rows[0].RecordCount -eq 4) 'Remaining record count was incorrect.'
    }
    catch {
        $scenarioFailure = $_
        $scenarioStage = $script:stage
        $script:liveRecord.FailedStage = $scenarioStage
    }
    finally {
        # Cleanup can only touch rows created under this unique run ID.
        Set-LiveStage 'cleanup' -Cleanup 'Running'
        try {
            $null = Invoke-LivePlan Delete ([pscustomobject]@{ CommandText = "DELETE FROM $table WHERE RunId = @RunId"; Parameters = $runParameter })
            $postCleanup = Invoke-LivePlan Query ([pscustomobject]@{ CommandText = "SELECT COUNT(*) AS RecordCount FROM $table WHERE RunId = @RunId"; Parameters = $runParameter })
            Assert ($postCleanup.ResultSets[0].Rows[0].RecordCount -eq 0) 'Scoped cleanup left records behind.'
            Set-LiveStage 'cleanup-verified' -Cleanup 'VerifiedEmpty'
        }
        catch {
            $cleanupFailure = $_
            Set-LiveStage 'cleanup-failed' -Cleanup 'Failed'
        }
    }
    if ($null -ne $scenarioFailure -or $null -ne $cleanupFailure -or $script:recordWriteFailed) {
        if ($null -eq $script:liveRecord.FailedStage) { $script:liveRecord.FailedStage = 'cleanup' }
        Set-LiveStage 'failed' -Result 'Failed'
        throw 'Live scenario or scoped cleanup failed.'
    }
    Set-LiveStage 'complete' -Result 'Passed'
    Write-Output 'PASS: live lazy route, genuine SqlClient operations, ingestion, result sets, Delete counts, rollback, JSON boundary, and scoped cleanup.'
}
catch {
    if ($null -ne $script:liveRecord) {
        if ($null -eq $script:liveRecord.FailedStage) { $script:liveRecord.FailedStage = $script:stage }
        $script:liveRecord.FailureClass = if ($script:liveRecord.FailedStage -in @('configuration','foundation-bootstrap','secrets-bootstrap','lazy-registration','target-validation','fixture-validation')) { 'EnvironmentOrFixture' } else { 'ScenarioOrAdapterNeedsDiagnosis' }
        Set-LiveStage 'failed' -Result 'Failed'
        Write-Output "FAIL: live Azure SQL class=$($script:liveRecord.FailureClass) stage=$($script:liveRecord.FailedStage) cleanup=$($script:liveRecord.Cleanup) run_id=$($script:liveRecord.RunId) record=$script:recordPath"
    }
    else { Write-Output "FAIL: live Azure SQL stage=$script:stage before run ID allocation." }
    exit 1
}
