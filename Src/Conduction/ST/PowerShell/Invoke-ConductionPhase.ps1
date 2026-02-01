function Invoke-ConductionPhaseSet {
    [CmdletBinding()]
    param (
        # Conduction Signal
        [Parameter(Mandatory)]
        [Signal]$Signal,

        # Phase Set Signal (contains array of Phase ItemSignals or phase objects)
        [Parameter(Mandatory)]
        [Signal]$ItemSignal,

        # Full plan object
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-ConductionPhaseSet", $Signal) | Select-Object -Last 1

    $phaseSet = $ItemSignal.GetJacketResult()

    foreach ($phaseSignal in $phaseSet) {
        $phaseJacketSignal = [Signal]::Start("Invoke-ConductionPhaseSet", $Signal) | Select-Object -Last 1
        $phaseJacketSignal.SetJacket($phaseSignal)
        
        # Passing through the original ItemSignal passed through the condenser/conduction for processing in the phases
        $phaseSignal.SetResult($ItemSignal)
        $phaseResult = Invoke-ConductionPhase `
            -Signal $Signal `
            -ItemSignal $phaseSignal `
            -Plan $Plan | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($phaseResult)) {
            return $opSignal
        }
    }

    return $opSignal
}


function Invoke-ConductionPhase {
    [CmdletBinding()]
    param (
        # ConductionSignal
        [Parameter(Mandatory)][Signal]$Signal,

        # Phase ItemSignal
        [Parameter(Mandatory)][Signal]$ItemSignal,

        # The full plan object (relay + phases + any global settings) - can stay object
        [Parameter(Mandatory)][object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-ConductionPhase", $Signal) | Select-Object -Last 1

    # ---- Helpers (Signal-safe; Resolve-PathFromDictionary only) ----

    function _Resolve-String {
        param([object]$Dict, [string]$Path)

        $s = Resolve-PathFromDictionary -Dictionary $Dict -Path $Path -SignalLevel "Warning" | Select-Object -Last 1
        if ($s -and $s.HasResult()) { return ("{0}" -f $s.GetResult()).Trim() }
        return ""
    }

    function _Resolve-Array {
        param([object]$Dict, [string]$Path)

        $s = Resolve-PathFromDictionary -Dictionary $Dict -Path $Path -SignalLevel "Warning" | Select-Object -Last 1
        if ($s -and $s.HasResult()) { return @($s.GetResult()) }
        return @()
    }

    function _Resolve-Order {
        param([object]$Dict)

        $o = Resolve-PathFromDictionary -Dictionary $Dict -Path "Order" -SignalLevel "Warning" | Select-Object -Last 1
        if ($o -and $o.HasResult()) {
            $raw = "{0}" -f $o.GetResult()
            $tmp = 0
            if ([int]::TryParse($raw, [ref]$tmp)) { return $tmp }
        }
        return 999999
    }

    # ---- Step Runner ----
    function Invoke-ConductionPhase_InvokeStep {
        param(
            [Parameter(Mandatory)] $Step,
            [Parameter(Mandatory)][Signal] $ItemSignal,
            [Parameter(Mandatory)] $Plan,
            [Parameter(Mandatory)][Signal] $Signal
        )

        $stepOpSignal = [Signal]::Start("Invoke-ConductionPhase:Step", $Signal) | Select-Object -Last 1
        <#
        $stepName = _Resolve-String -Dict $Step -Path "%.@.Name"
        $action = _Resolve-String -Dict $Step -Path "%.@.Action"
        $activity = _Resolve-String -Dict $Step -Path "%.@.Activity"
        $virtualPath = _Resolve-String -Dict $Step -Path "%.@.VirtualPath"
#>
        $stepName = _Resolve-String -Dict $Plan -Path "Name"
        $action = _Resolve-String -Dict $Plan -Path "Action" # If Action is Empty, Adapter is used to executate an adapter call
        $activity = _Resolve-String -Dict $Plan -Path "Activity"
        $adapter = _Resolve-String -Dict $Plan -Path "Adapter"
        $virtualPath = _Resolve-String -Dict $Plan -Path "%.@.VirtualPath"

        if ([string]::IsNullOrWhiteSpace($activity)) { return $stepOpSignal.LogInformation("Step '$stepName' missing Activity.") }
        if ([string]::IsNullOrWhiteSpace($stepName)) { $stepName = "UnnamedStep" }
        if ([string]::IsNullOrWhiteSpace($activity)) { return $stepOpSignal.LogInformation("Step '$stepName' missing Activity.") }
        #        if ([string]::IsNullOrWhiteSpace($virtualPath)) { return $stepOpSignal.LogCritical("Step '$stepName' missing VirtualPath.") }
        if ([string]::IsNullOrWhiteSpace($action)) { $action = "Invoke-MappedAdapter" }

        # Provide execution context on the Step object (no raw mutation elsewhere)
#        Add-PathToDictionary -Dictionary $Step -Path "Config.Signal"     -Value $Signal     | Out-Null
#        Add-PathToDictionary -Dictionary $Step -Path "Config.ItemSignal" -Value $ItemSignal | Out-Null
#        Add-PathToDictionary -Dictionary $Step -Path "Config.Plan"       -Value $Plan       | Out-Null

        $resultSignal = $null
        try {
            switch ($action) {
                "Invoke-MappedAdapter" {
                    # Expected to return [Signal]
                    $resultSignal = Invoke-MappedAdapter `
                        -Signal $Signal `
                        -ItemSignal $ItemSignal `
                        -Name $stepName `
                        -Activity $activity `
                        -Adapter $adapter `
                        -Plan $Plan | Select-Object -Last 1

                }

                default {
                    $cmdSignal = Resolve-Function -FunctionName $action 
                    $cmd = $cmdSignal.GetResult()
                    $resultSignal = & $cmd -Signal $Signal -ItemSignal $ItemSignal -Plan $Plan | Select-Object -Last 1
                }
            }

            $stepOpSignal.MergeSignal($resultSignal) | Out-Null

            if ($resultSignal -and $resultSignal.Success()) {
                Add-PathToDictionary -Dictionary $Step -Path "Status" -Value "Success" | Out-Null
            }
            else {
                Add-PathToDictionary -Dictionary $Step -Path "Status" -Value "Failed" | Out-Null
            }

            return $stepOpSignal
        }
        catch {
            $stepOpSignal.LogCritical("Exception executing step '$stepName': $_") | Out-Null
            Add-PathToDictionary -Dictionary $Step -Path "Status" -Value "Failed" | Out-Null
            return $stepOpSignal
        }
    }

    # ---- Main ----

    $ErrorLog = @()
    $success = $true

    try {
        if ($null -eq $Signal) { return $opSignal.LogCritical("Signal is null.") }
        if ($null -eq $ItemSignal) { return $opSignal.LogCritical("ItemSignal is null.") }

        # Phase dictionary lives in ItemSignal.Result (per your architecture)
        $phaseDictSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@" -SignalLevel "Warning" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($phaseDictSignal)) {
            return $opSignal.LogCritical("Failed to resolve Phase dictionary from ItemSignal.")
        }

        $phaseDict = $phaseDictSignal.GetResult()

        # ---- Pre-mappings ----
        # Use the set ItemSignal if it exists, otherwise start a new target signal
        $TargetSignal = [Signal]::Start("Resolve-ConductionPlanRoute.Target", $opSignal) | Select-Object -Last 1

        # Nicely fit the Original Item into the jacket of the target to pass through the conduction phases.
        if ($ItemSignal.HasResult()) {
            $originalItemSignal = $ItemSignal.GetResult()
            if ($originalItemSignal.HasResult())
            {
                # TODO: Review the chain to figure out why/where the result is in the result.
                $originalItemSignal = $originalItemSignal.GetResult()
            }

            $TargetSignal = $originalItemSignal
        }

        $sourceSignal = Invoke-CondenserAdapter `
            -Slot "Memory" `
            -Activity "Generate" `
            -Signal $Signal `
            -Plan $phaseDict `
            -ItemSignal $TargetSignal `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($sourceSignal))) {
            $opSignal.LogCritical("⚠️ Memory.Generate failed while resolving ConductionPlan.")
            return $opSignal
        }

        <##>
        # ---- Steps (ordered) ----
        $stepsSignal = Resolve-PathFromDictionary -Dictionary $phaseDict -Path "Steps" | Select-Object -Last 1

        $steps = $stepsSignal.GetResult()
        $stepsSorted = $steps | Sort-Object -Property `
        @{ Expression = { _Resolve-Order -Dict $_ } },
        @{ Expression = { _Resolve-String -Dict $_ -Path "Name" } }

        foreach ($s in @($stepsSorted)) {
            $stepName = Resolve-PathFromDictionary -Dictionary $s -Path "Name"

            $stepSignal = Invoke-ConductionPhase_InvokeStep -Step $s -ItemSignal $ItemSignal -Plan $s -Signal $Signal | Select-Object -Last 1
            $opSignal.MergeSignal($stepSignal) | Out-Null

            if (-not $stepSignal.Success()) {
                $success = $false
                $ErrorLog += "Step failed: $stepName"
                # Optional fail-fast:
                # break
            }
        }
        #>
        # ---- Post-mappings ----
        $postMappingsSignal = Resolve-PathFromDictionary -Dictionary $phaseDict -Path "PostMappings" -SignalLevel "Information" | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($postMappingsSignal))) {
            $opSignal.LogCritical("⚠️ Memory.Generate failed while resolving PostMappings.")
            return $opSignal
        }

        $PostPlan = [pscustomobject]@{
            Mappings         = ($postMappingsSignal.GetResult())
            ReturnItemSignal = $true
        }

        if ($postMappingsSignal.HasResult()) {
            $sourceSignal = Invoke-CondenserAdapter `
                -Slot "Memory" `
                -Activity "Generate" `
                -Signal $Signal `
                -Plan $PostPlan `
                -ItemSignal $TargetSignal `
            | Select-Object -Last 1

            if ($opSignal.MergeSignalAndVerifyFailure(@($sourceSignal))) {
                $opSignal.LogCritical("⚠️ Memory.Generate failed while resolving PostMappings.")
                return $opSignal
            }
        }

        # Write Status/ErrorLog back onto the PHASE DICTIONARY, then set it back into ItemSignal.Result (so callers see updates)
        Add-PathToDictionary -Dictionary $phaseDict -Path "Status" -Value ($success ? "Success" : "Failed") | Out-Null

        if ($ErrorLog.Count -gt 0) {
            Add-PathToDictionary -Dictionary $phaseDict -Path "ErrorLog" -Value $ErrorLog | Out-Null
        }

        # Persist updated phase dict into the ItemSignal.Result (so the returned item signal contains the updated phase)
        $ItemSignal.SetResult($phaseDict) | Out-Null
    }
    catch {
        $success = $false
        $exception = $_.Exception.InnerException ?? $_.Exception
        if ($null -eq $exception) { $exception = $_ }

        $ErrorLog += ("Failed during phase execution: " + $exception.Message)

        try {
            $phaseDictSignal2 = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "@." -SignalLevel "Warning" | Select-Object -Last 1
            if ($phaseDictSignal2 -and $phaseDictSignal2.HasResult()) {
                $phaseDict2 = $phaseDictSignal2.GetResult()
                Add-PathToDictionary -Dictionary $phaseDict2 -Path "Status" -Value "Failed" | Out-Null
                Add-PathToDictionary -Dictionary $phaseDict2 -Path "ErrorLog" -Value $ErrorLog | Out-Null
                $ItemSignal.SetResult($phaseDict2) | Out-Null
            }
        }
        catch { }

        $opSignal.LogCritical("🔥 Exception during Invoke-ConductionPhase: $($exception.Message)") | Out-Null
    }

    # Per requirement: return the phase (ItemSignal) in opSignal result
    $opSignal.SetResult($ItemSignal) | Out-Null
    return $opSignal
}
