function Invoke-Data_AzureDataExplorer {
    param (
        [Signal]$Signal,
        [string]$Slot,
        [string]$Activity,  
        [object]$Plan,
        [Signal]$ItemSignal
    )

    $opSignal = [Signal]::Start("Invoke-Data_AzureDataExplorer") | Select-Object -Last 1

    try { 
        if ($null -eq $Signal) {
            return $opSignal.LogCritical("Cannot invoke Data_AzureDataExplorer — provided ConductionSignal is null.")
        }

        $ItemSignal = $ItemSignal ?? $Signal.GetJacket()

        # Convert the 

        $GridPlan = [PSCustomObject]@{
            Name           = "GridPhases"
            Description    = "Places the phases in the Grid (of the ItemSignal)"
            SourceAdapter  = "Condenser.Conduit"
            SourceActivity = "Graph"
            Path           = "@.Phases"
            Key            = "Adapters"
            TargetPath     = "*.Phases"
        }


        # Generate a Signal Graph of the Phases
        $gridResultSignal = Invoke-CondenserAdapter -Slot "Conduit" -Activity "Graph" -Signal $Signal -Plan $GridPlan -ItemSignal $ItemSignal | Select-Object -Last 1
        $gridSignal = $gridResultSignal.GetResult()

        $phasesSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "@.Phases" | Select-Object -Last 1
#        $phasesFlatArray = $phasesSignal.GetResult($true)

        $phaseGraphSignal = Invoke-Data_AzureDataExplorer_GetNextPhaseSet -DependsOn "" -PhaseArraySignal $phasesSignal

        $invokeResultSignal = Invoke-ConductionPhaseSet -Signal $Signal -ItemSignal $phaseGraphSignal -Plan $Plan | Select-Object -Last 1
        $opSignal.MergeSignal($invokeResultSignal)

        <#

        function Invoke-Data_AzureDataExplorer_ExecutePhaseSet {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [Signal] $opSignal,
                [Parameter(Mandatory)]          $phaseGraphSignal,
                [Parameter(Mandatory)]          $Conductor,
                $Phases = $null,
                $Slot

            )


            if ($null -eq $Phases) {
                # Get current phase set
                $phaseListSignal = Invoke-Data_AzureDataExplorer_GetNextPhaseSet -phaseGraphSignal $phaseGraphSignal -Slot $Slot | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($phaseListSignal)) {
                    $opSignal.LogCritical("Failed to resolve next phase set from ConductionPlan.")
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
                $innerPhaseListSignal = Invoke-Data_AzureDataExplorer_GetNextPhaseSet -phaseGraphSignal $phaseGraphSignal -CurrentPhaseSignal $phase | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($innerPhaseListSignal)) {
                    $opSignal.LogCritical("Failed to resolve next phase set from ConductionPlan.")
                    return $opSignal
                }

                $innerPhases = $innerPhaseListSignal.GetResult()

                ## Perform Recursive Execution of inner phases
                if ($innerPhases.Count) {
                    $null = Invoke-Data_AzureDataExplorer_ExecutePhaseSet -opSignal $opSignal -phaseGraphSignal $phaseGraphSignal -Phases $innerPhases -Conductor $Conductor
                }
            }

            # If you have an outputs aggregator, plug it back in here:
            # $resultSignal = Invoke-AllCommandStepOutputs -Phases $phases
            # Placeholder so the existing failure check remains intact:
            $resultSignal = $opSignal

            if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                $opSignal.LogCritical("Failed to process all command step outputs.")
                return $opSignal
            }
            #    }

            return $opSignal
        }

        $invokeResultSignal = Invoke-ConductionPhaseSet -Signal $Signal -ItemSignal $phaseGraphSignal -Plan $Plan | Select-Object -Last 1
        $opSignal.MergeSignal($invokeResultSignal)

      #  $InvokeResult = Invoke-ConductionPhase -Signal $Signal -ItemSignal $phaseGraphSignal -Plan $Plan | Select-Object -Last 1
#        Invoke-Data_AzureDataExplorer_ExecutePhaseSet -opSignal $opSignal -phaseGraphSignal $phaseGraphSignal -Conductor $Conductor -Slot $Slot | Select-Object -Last 1

        ############################################################        
        $phaseListSignal = Invoke-Data_AzureDataExplorer_GetNextPhaseSet -phaseGraphSignal $phaseGraphSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($phaseListSignal)) {
            $opSignal.LogCritical("Failed to resolve next phase set from ConductionPlan.")
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

                $innerPhaseListSignal = Invoke-Data_AzureDataExplorer_GetNextPhaseSet -phaseGraphSignal $phaseGraphSignal  | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($phaseListSignal)) {
                    $opSignal.LogCritical("Failed to resolve next phase set from ConductionPlan.")
                    return $opSignal
                }

                $innerPhases = $innerPhaseListSignal.GetResult()

                ## Perform Recusive Exeuction of inner phases
            }
        
            #$resultSignal = Invoke-AllCommandStepOutputs -Phases $phases
            
            if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                $opSignal.LogCritical("Failed to process all command step outputs.")
                return $opSignal
            }
        }
    
        $opSignal.SetResult($resultSignal.GetResult())
        $opSignal.LogInformation("✅ Invoked Data_AzureDataExplorer successfully.")

#>


    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-Data_AzureDataExplorer: $_", $null, $_)
    }

    return $opSignal
}
