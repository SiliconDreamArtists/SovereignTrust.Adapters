function Invoke-Conduction_ST_GetNextPhaseSet {
    param (
        [Signal]$CurrentPhaseSignal,
        [Signal]$PhaseGraphSignal,
        [string]$Dependencies,
        [bool]$NoDependents,
        [bool]$ShowDetails = $false,
        [string]$Slot
    )

    $opSignal = [Signal]::Start("Invoke-Conduction_ST_GetNextPhaseSet") | Select-Object -Last 1

    $phasesGraphSignal = Resolve-PathFromDictionary -Dictionary $PhaseGraphSignal -Path "@.#" | Select-Object -Last 1
    $phasesGraph = $phasesGraphSignal.GetResult()

    # Create a lookup dictionary for Name → Object
    $phaseMap = @{}

    foreach ($phaseKey in $phasesGraph.Keys) {
        $phase = $phasesGraph[$phaseKey]
        if ($phase.Name) {
            $phaseMap[$phase.Name] = $phase
        }
    }

    $filteredSteps = $phasesGraph

    $verb = ""
    $slotParts = @()

    if ($null -ne $Slot -and "" -ne $Slot)
    {
        $slotParts = $Slot -Split "\."
        $slotParts = @($slotParts)
        if ($slotParts.Count -gt 1)
        {
            $verb = $slotParts[1]
        }
    }

    $dependsOn = ""
    if ($null -ne $CurrentPhaseSignal)
    {
        $dependsOnSignal = Resolve-PathFromDictionary -Dictionary $CurrentPhaseSignal -Path "%.@.Name" | Select-Object -Last 1 
        $dependsOn = $dependsOnSignal.GetResult()
    }
    

    # --- Filter: Dependencies (pull dependency chain of a given step name) ---
    if ($Dependencies) {
        if (-not $phaseMap.ContainsKey($Dependencies)) {
            throw "Dependency '$Dependencies' not found in the step list."
        }

        $dependencyNames = $phaseMap[$Dependencies].DependsOn
        if (-not $dependencyNames) {
            Write-Warning "Step '$Dependencies' has no dependencies."
            $filteredSteps = @()
        } else {
            $filteredSteps = @()
            foreach ($dep in $dependencyNames) {
                if ($phaseMap.ContainsKey($dep)) {
                    $filteredSteps += $phaseMap[$dep]
                }
            }
        }
    }

    # --- Filter: NoDependents (only show steps that are NOT referenced in any DependsOn list) ---
    if ($NoDependents) {
        $allDeps = $JsonArray | ForEach-Object { $_.DependsOn } | Where-Object { $_ } | Select-Object -Unique
        $filteredSteps = $filteredSteps | Where-Object { $allDeps -notcontains $_.Name }
    }

    if ($null -ne $verb -or $null -ne $dependsOn)
    {
        $newFilteredSteps = [ordered]@{}

        foreach ($phaseKey in $filteredSteps.Keys) {
            # If verb is empty, and depends on is empty, we want to get any phases with an empty verb
            # If verb is not empty, match it to name.
            $phaseSignal = $filteredSteps[$phaseKey]

            $phaseIsDefault = $false
            $phaseIsDefaultSignal = Resolve-PathFromDictionary -Dictionary $phaseSignal -Path "%.@.IsDefault" -FailureLogLevel "Verbose" | Select-Object -Last 1
            if ($phaseIsDefaultSignal.HasResult()) {
                $phaseIsDefault = $phaseIsDefaultSignal.GetResult()
                $phaseIsDefault = $phaseIsDefault -or $phaseIsDefault -eq "true"
            }

            $phaseDependsOnSignal = Resolve-PathFromDictionary -Dictionary $phaseSignal -Path "%.@.DependsOn" -FailureLogLevel "Verbose" | Select-Object -Last 1
            $phaseDependsOn = @{}
            if ($phaseDependsOnSignal.HasResult()) {
                $phaseDependsOn = $phaseDependsOnSignal.GetResult() -Split '\,' | ForEach-Object { $_.Trim() }
                #force to be an array.
                $phaseDependsOn = @($phaseDependsOn)
            }

            $phaseNameSignal = Resolve-PathFromDictionary -Dictionary $phaseSignal -Path "%.@.Name" -FailureLogLevel "Verbose" | Select-Object -Last 1
            $phaseName = $null
            if ($phaseNameSignal.HasResult()) {
                $phaseName = $phaseNameSignal.GetResult() -Split '\,' | ForEach-Object { $_.Trim() }
                #force to be an array.
                $phaseName = @($phaseName)
            }

            $includePhase = $false
            if ($verb -eq "" -and $dependsOn -eq "" -and $phaseDependsOn -eq "") {
                $includePhase = $true
            }

            if ($verb -ne "" -and $phaseName -eq $verb) {
                $includePhase = $true
            }

            # Add PhaseDependsOn * when verb isn't set
            if ($phaseDependsOn -contains "*" -and "" -eq $verb) {
                $includePhase = $true
            }

            if ($phaseDependsOn -contains $dependsOn) {
                $includePhase = $true
            }

            if ($verb -eq "" -and $dependsOn -eq "" -and ($phaseIsDefault -or -not $phaseDependsOn.Count)) {
                $includePhase = $true
            }

            if ($includePhase)
            {
                $newFilteredSteps[$phaseKey] = $phaseSignal
            }
        }

        $filteredSteps = $newFilteredSteps
    }

    <#
        # Normalize caller inputs
    $verb      = ($verb ?? '').Trim()
    $dependsOn = ($dependsOn ?? '').Trim()

    # Only run if either filter is provided; remove this outer if if you want it to always run
    if ($null -ne $verb -or $null -ne $dependsOn)
        $newFilteredSteps = [ordered]@{}

        foreach ($phaseKey in $filteredSteps.Keys) {
            $phaseSignal = $filteredSteps[$phaseKey]

            # Resolve DependsOn and turn into a clean string[] (or empty @())
            $depSignal = Resolve-PathFromDictionary -Dictionary $phaseSignal -Path "%.@.DependsOn" | Select-Object -Last 1
            $deps = @()
            if ($depSignal.HasResult()) {
                $raw = $depSignal.GetResult()
                if ($raw -is [string]) {
                    $deps = $raw -split '\s*,\s*' | Where-Object { $_ }
                }
                elseif ($raw -is [System.Collections.IEnumerable]) {
                    $deps = @($raw) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
                }
            }

            $noInputs = ($verb -eq '' -and $dependsOn -eq '')
            $noDeps   = -not $deps.Count

            $include = $false

            # 1) No filters + no deps on phase
            if ($noInputs -and $noDeps) { $include = $true }

            # 2) Verb matches phase name
            elseif ($verb -ne '' -and $phaseSignal.GetResult().Name -eq $verb) { $include = $true }

            # 3) DependsOn contains * (treat as wildcard all)
            elseif ($deps -contains '*') { $include = $true }

            # 4) Exact dependsOn match (add -like/-match if you want patterns)
            elseif ($dependsOn -ne '' -and $deps -contains $dependsOn) { $include = $true }

            if ($include) {
                $newFilteredSteps[$phaseKey] = $phaseSignal
            }
        }

        $filteredSteps = $newFilteredSteps
    }

    #>

    $opSignal.SetResult($filteredSteps) | Out-Null

    return $opSignal

    #return $filteredSteps
    # --- Output Numbered List ---
    $i = 1
    foreach ($phaseKey in $filteredSteps.Keys) {
        $phaseSignal = $filteredSteps[$phaseKey]
        Write-Host "$i) : $($phase.Title)" -ForegroundColor Cyan

        if ($ShowDetails)
        {
            Write-Host "  Name: $($phase.Name)"
            Write-Host "  Property: $($phase.Property)"
            Write-Host "  Template: $($phase.TemplatePath)"
            Write-Host "  Type: $($phase.Type)"
            Write-Host "  Target: $($phase.Target)"
            Write-Host "  AutomationLevel: $($phase.AutomationLevel)"
            if ($phase.DependsOn) {
                Write-Host "  DependsOn: $($phase.DependsOn -join ', ')"
            }
            if ($phase.Process) {
                Write-Host "  Process.Template: $($phase.Process.TemplatePath)"
                Write-Host "  Process.XPath:    $($phase.Process.TemplateXPath)"
                Write-Host "  Process.Type:     $($phase.Process.TemplateType)"
            }
            }

        Write-Host ""
        $i++
    }
}
