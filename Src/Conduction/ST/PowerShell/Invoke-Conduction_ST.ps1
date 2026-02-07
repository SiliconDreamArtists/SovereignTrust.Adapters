function Invoke-Conduction_ST {
    param (
        [Signal]$Signal,
        [string]$Slot,
        [string]$Activity,  
        [object]$Plan,
        [Signal]$ItemSignal
    )

    $opSignal = [Signal]::Start("Conduction_ST:$($Plan.Name)") | Select-Object -Last 1

    $conductorSignal = $Signal.GetControl($true)

    $SkipTelemetrySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "ExcludeFromTelemetry" -SignalLevel "Information" -Default $false | Select-Object -Last 1

    $conductionSignal = [Signal]::Start("Conduction_ST:$($Plan.Name)") | Select-Object -Last 1
    $conductionSignal.SetControl($conductorSignal)

    if (-not $SkipTelemetrySignal.GetResult()) {
        $conductionSignal.AddTag("Conduction")
        $conductionSignal.AddProperty("SignalType", "Conduction")
        $conductionSignal.AddProperty("ConductionId", $conductionSignal.Id)
        $conductionSignal.AddProperty("OperationId", $conductionSignal.Id)
        $conductionSignal.AddProperty("State", "Started")
        $conductionSignal.AddProperty("StartedAt", [DateTime]::UtcNow)
        $conductionSignal.AddProperty("PlanId", $Plan.Id)
        $conductionSignal.AddProperty("PlanName", $Plan.Name)

        Invoke-Telemetry -Signal $Signal -ItemSignal $conductionSignal
    }

    try { 
        if ($null -eq $Signal) {
            return $opSignal.LogCritical("Cannot invoke Conduction_ST — provided ConductionSignal is null.")
        }

        #$ItemSignal = $ItemSignal ?? $Signal.GetJacket()

        # Convert the 

        $GridPlan = [PSCustomObject]@{
            Name           = "GridPhases"
            Description    = "Places the phases in the Grid (of the ItemSignal)"
            SourceAdapter  = "Condenser.Conduit"
            SourceActivity = "Graph"
            Path           = "%.@.Phases"
            Key            = "Adapters"
        }


        $ConductionPlanSignal = [Signal]::Start("Conduction Plan Signal") | Select-Object -Last 1
        $ConductionPlanSignal.SetJacketResult($Plan)
        
        $continue = $true

        # Generate a Signal Graph of the Phases
        $gridResultSignal = Invoke-CondenserAdapter -Slot "Conduit" -Activity "Graph" -Signal $conductionSignal -Plan $GridPlan -ItemSignal $ConductionPlanSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($gridResultSignal)) { return $opSignal }

        $phasesSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Phases" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($phasesSignal)) { return $opSignal }
        
        function Invoke-ProcessPhaseSetDependsOn
        {
            param (
                [Signal]$conductionSignal,
                [Signal]$opSignal,
                [Signal]$phasesSignal,  
                [Signal]$gridResultSignal,
                [Signal]$ItemSignal,
                [object]$Plan,
                [string]$DependsOn
            )

                $phaseGraphJacketSignal = Invoke-Conduction_ST_GetNextPhaseSet -DependsOn $DependsOn -PhaseArraySignal $phasesSignal -PhasesGridSignal $gridResultSignal
                if ($opSignal.MergeSignalAndVerifyFailure($phaseGraphJacketSignal)) { return $opSignal }

                if (($phaseGraphJacketSignal.GetResult()).Count -eq 0)
                {
                    return $opSignal
                }

                $phaseGraphSignal = [Signal]::Start("Conduction Plan Signal") | Select-Object -Last 1
                $phaseGraphSignal.SetJacket($phaseGraphJacketSignal)
                
                # Pass the original $ItemSignal through the result in the PhaseGraphSignal (The jacket contains the phase graph set)
                $phaseGraphSignal.SetResult($ItemSignal)
                $invokeResultSignal = Invoke-ConductionPhaseSet -Signal $conductionSignal -ItemSignal $phaseGraphSignal -Plan $Plan | Select-Object -Last 1
                $opSignal.MergeSignal($invokeResultSignal)

                # TODO: Instead of test for success, pass through result state so that the dependends can determine if they should be used for healing, etc.
                if ($invokeResultSignal.Success()) {
                    $items = $phaseGraphSignal.GetJacket().GetResult()

                foreach ($dependsOnItemSignal in $items) {
                        $dependsOnItemSignal = Resolve-PathFromDictionary -Dictionary $dependsOnItemSignal -Path "%.@.Name" | Select-Object -Last 1
                        Invoke-ProcessPhaseSetDependsOn -conductionSignal $conductionSignal -opSignal $opSignal -phasesSignal $phasesSignal -gridResultSignal $gridResultSignal -ItemSignal $ItemSignal -Plan $Plan -DependsOn $dependsOnItemSignal.GetResult()
                    }
                }

                    return $opSignal
        }

        Invoke-ProcessPhaseSetDependsOn -conductionSignal $conductionSignal -opSignal $opSignal -phasesSignal $phasesSignal -gridResultSignal $gridResultSignal -ItemSignal $ItemSignal -Plan $Plan -DependsOn ""

        if (-not $SkipTelemetrySignal.GetResult()) {
            $conductionSignal.MergeSignal($opSignal, $null, "Skip")
            $conductionSignal.AddProperty("State", "Completed")
            $conductionSignal.AddProperty("EndedAt", [DateTime]::UtcNow)
            Invoke-Telemetry -Signal $Signal -ItemSignal $conductionSignal
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-Conduction_ST: $_", $null, $_)
    }

    return $opSignal
}
