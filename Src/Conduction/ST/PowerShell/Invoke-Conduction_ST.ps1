function Invoke-Conduction_ST {

    param (
        [object]$Conductor,
        [object]$Conduit,
        [Signal]$ConductionSignal,
        $Slot
    )

    $opSignal = [Signal]::Start("Invoke-Conduction_ST") | Select-Object -Last 1

    try { 
        if ($null -eq $Conductor) {
            return $opSignal.LogCritical("Cannot invoke Conduction_ST — provided Conductor is null.")
        } 

        if ($null -eq $ConductionSignal) {
            return $opSignal.LogCritical("Cannot invoke Conduction_ST — provided ConductionSignal is null.")
        }

        $itemSignal = $ConductionSignal.GetJacket()

        # Choose which Signal to mine the jacket of to find the conduction plan.
        $conductionJacket = $itemSignal
        if (-not $itemSignal.HasJacket()) {
            $conductionJacket = $ConductionSignal
        }

        $planSignal = Resolve-PathFromDictionary -Dictionary $conductionJacket -Path "%.@.ConductionPlan" | Select-Object -Last 1


        $GridPlan = [PSCustomObject]@{
            SourcesWirePath           = "ConductionPlan"
            SourcesWirePathTemplate   = "%.%.@.{0}"
            SourcesIdentifierWirePath = "Name"
        }

        #                $planSignal = [Signal]::Start("Invoke-MessageResponse", $ConductionSignal) | Select-Object -Last 1
        #                $planSignal.SetResult($Plan)
                
        $gridConductionPlanSignal = Invoke-GridCondenser -Signal $ConductionSignal -Plan $GridPlan -ItemSignal $conductionJacket -PlanWirePathPrefix "%.%.@" | Select-Object -Last 1
   
        $gridConductionPlanSignalSignal = Resolve-PathFromDictionary -Dictionary $gridConductionPlanSignal -Path "@.*.#" | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($phasesSignal)) {
            $opSignal.LogCritical("❌ Failed to resolve 'Phases' from ConductionSignal.")
            return $opSignal
        }

<#
        $verb = ""
        $verbSignal = Resolve-PathFromDictionary -Dictionary $ConductionSignal -Path "@.Verb" -FailureLogLevel "Verbose" | Select-Object -Last 1

        if ($verbSignal.HasResult()) {
            $verb = $verbSignal.GetResult()
        }
#>
        # Update this to follow the way that Condensers run.
        $phases = $gridConductionPlanSignalSignal.GetResult()
    
        $phaseGraph = $gridConductionPlanSignal.GetResult().GetPointer()
        $phaseGraphSignal = [Signal]::Start("Invoke-Conduction_ST:PhaseGraphSignal") | Select-Object -Last 1
        $phaseGraphSignal.SetResult($phaseGraph)

        $phaseGraphSignalJacket = [Signal]::Start("Invoke-Conduction_ST:PhaseGraphSignal") | Select-Object -Last 1
 #       Add-PathToDictionary -Dictionary $phaseGraphSignalJacket -Path "@.Verb" -Value $verb

        $phaseGraphSignal.SetJacket($phaseGraphSignalJacket)

        function Invoke-Conduction_ST_ExecutePhaseSet {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [Signal] $opSignal,
                [Parameter(Mandatory)]          $PhaseGraphSignal,
                [Parameter(Mandatory)]          $Conductor,
                $Phases = $null,
                $Slot
            )


            if ($null -eq $Phases) {
                # Get current phase set
                $phaseListSignal = Invoke-Conduction_ST_GetNextPhaseSet -PhaseGraphSignal $PhaseGraphSignal -Slot $Slot | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($phaseListSignal)) {
                    $opSignal.LogCritical("❌ Failed to resolve next phase set from ConductionPlan.")
                    return $opSignal
                }

                $Phases = $phaseListSignal.GetResult()
            }

            # Base case: nothing to do
            if (-not $Phases.Count) {
                return $opSignal
            }

            #    while ($phases.Count) {
            foreach ($phaseKey in $Phases.Keys) {
                $phase = $Phases[$phaseKey]
                $opSignal.LogInformation("➡️ Processing phase: $($phase.Name)")

                $commandSignal = Resolve-PathFromDictionary -Dictionary $phase -Path "%.@.Type" | Select-Object -Last 1
                $commandResult = $commandSignal.GetResult()

                $command = "$commandResult -Signal `$phase -Conductor `$Conductor"
                Write-Host "[agent] Executing resolved command: $command" -ForegroundColor Cyan
                $result = Invoke-Expression $command | Select-Object -Last 1
                Write-Host "[agent] Resolved command executed successfully." -ForegroundColor Green

                # Fetch inner phase set and recurse
                $innerPhaseListSignal = Invoke-Conduction_ST_GetNextPhaseSet -PhaseGraphSignal $PhaseGraphSignal -CurrentPhaseSignal $phase | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($innerPhaseListSignal)) {
                    $opSignal.LogCritical("❌ Failed to resolve next phase set from ConductionPlan.")
                    return $opSignal
                }

                $innerPhases = $innerPhaseListSignal.GetResult()

                ## Perform Recursive Execution of inner phases
                if ($innerPhases.Count) {
                    $null = Invoke-Conduction_ST_ExecutePhaseSet -opSignal $opSignal -PhaseGraphSignal $PhaseGraphSignal -Phases $innerPhases -Conductor $Conductor
                }
            }

            # If you have an outputs aggregator, plug it back in here:
            # $resultSignal = Invoke-AllCommandStepOutputs -Phases $phases
            # Placeholder so the existing failure check remains intact:
            $resultSignal = $opSignal

            if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                $opSignal.LogCritical("⚠️ Failed to process all command step outputs.")
                return $opSignal
            }
            #    }

            return $opSignal
        }

        Invoke-Conduction_ST_ExecutePhaseSet -opSignal $opSignal -PhaseGraphSignal $phaseGraphSignal -Conductor $Conductor -Slot $Slot | Select-Object -Last 1

        ############################################################        
        $phaseListSignal = Invoke-Conduction_ST_GetNextPhaseSet -PhaseGraphSignal $phaseGraphSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($phaseListSignal)) {
            $opSignal.LogCritical("❌ Failed to resolve next phase set from ConductionPlan.")
            return $opSignal
        }

        $phases = $phaseListSignal.GetResult()

        while ($phases.Count) {
            foreach ($phaseKey in $phases.Keys) {
                $phase = $phases[$phaseKey]
                $opSignal.LogInformation("➡️ Processing phase: $($phase.Name)")

                $commandSignal = Resolve-PathFromDictionary -Dictionary $phase -Path "%.@.Type" | Select-Object -Last 1
                $commandResult = $commandSignal.GetResult()

                $command = "$commandResult -Signal `$phase -Conductor `$Conductor"
                Write-Host "[agent] Executing resolved command: $command" -ForegroundColor Cyan
                $result = Invoke-Expression $command | Select-Object -Last 1
                Write-Host "[agent] Resolved command executed successfully." -ForegroundColor Green

                $innerPhaseListSignal = Invoke-Conduction_ST_GetNextPhaseSet -PhaseGraphSignal $phaseGraphSignal  | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($phaseListSignal)) {
                    $opSignal.LogCritical("❌ Failed to resolve next phase set from ConductionPlan.")
                    return $opSignal
                }

                $innerPhases = $innerPhaseListSignal.GetResult()

                ## Perform Recusive Exeuction of inner phases
            }
        
            #$resultSignal = Invoke-AllCommandStepOutputs -Phases $phases
            
            if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                $opSignal.LogCritical("⚠️ Failed to process all command step outputs.")
                return $opSignal
            }
        }
    
        $opSignal.SetResult($resultSignal.GetResult())
        $opSignal.LogInformation("✅ Invoked Conduction_ST successfully.")


    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-Conduction_ST: $_")
    }

    return $opSignal
}
