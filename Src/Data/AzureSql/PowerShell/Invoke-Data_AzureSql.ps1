# Private execution seam. Later connection and operation work replaces this
# implementation; tests can substitute this function within module scope.
# It receives the hydrated jacket, unmodified plan/config, and signals.
function Invoke-AzureSqlExecution {
    param(
        [object]$Adapter, [string]$Slot, [string]$Activity,
        [object]$Config, [object]$Plan,
        [Signal]$ConductionSignal, [Signal]$ItemSignal
    )
    throw 'Azure SQL execution is not implemented yet.'
}

function Invoke-Data_AzureSql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Adapter,
        [Parameter(Mandatory)][string]$Slot,
        [Parameter(Mandatory)][string]$Activity,
        [Parameter(Mandatory)][Signal]$ConductionSignal,
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][Signal]$ItemSignal
    )

    $opSignal = [Signal]::Start("Data_AzureSql.Invoke:$Slot.$Activity", $ItemSignal) | Select-Object -Last 1
    try {
        if ($Activity -notin @('Write', 'Query', 'Delete')) {
            throw "Unsupported AzureSql activity '$Activity'."
        }
        $config = Get-AzureSqlObjectValue $Plan 'Config'
        if ($null -eq $config) { throw 'AzureSql requires Plan.Config.' }
        if ($Activity -eq 'Write') {
            if ([string]::IsNullOrWhiteSpace([string](Get-AzureSqlObjectValue $config 'Procedure'))) {
                throw 'Write requires Config.Procedure.'
            }
        }
        elseif ([string]::IsNullOrWhiteSpace([string](Get-AzureSqlObjectValue $config 'CommandText'))) {
            throw "$Activity requires Config.CommandText."
        }

        $result = Invoke-AzureSqlExecution -Adapter $Adapter -Slot $Slot -Activity $Activity `
            -Config $config -Plan $Plan -ConductionSignal $ConductionSignal -ItemSignal $ItemSignal
        if ($result -is [Signal]) {
            if ($opSignal.MergeSignalAndVerifyFailure($result)) { return $opSignal }
            if (-not $result.HasResult()) { throw 'Azure SQL execution returned no result.' }
            $result = $result.GetResult()
        }
        if ($result -isnot [string]) { throw 'Azure SQL execution must return JSON text.' }
        $null = $result | ConvertFrom-Json -Depth 100
        $opSignal.SetResult($result)
    }
    catch {
        $null = $opSignal.LogCritical("AzureSql $Activity failed: $($_.Exception.Message)", $null, $_)
    }
    return $opSignal
}
