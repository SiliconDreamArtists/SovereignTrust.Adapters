
. "$PSScriptRoot\..\..\..\..\..\SignalGraph\Src\PowerShell\Classes\SignalEntry.ps1"
. "$PSScriptRoot\..\..\..\..\..\SignalGraph\Src\PowerShell\Classes\Signal.ps1"
. "$PSScriptRoot\..\..\..\..\..\SignalGraph\Src\PowerShell\Classes\Graph.ps1"

$sgModuleName = 'SignalGraph'
if (-not (Get-Module -Name $sgModuleName)) {
    $sgPath = Join-Path $PSScriptRoot "../../../../../SignalGraph/Src/PowerShell/SignalGraph.psd1"
    Import-Module (Resolve-Path $sgPath).ProviderPath -Force
}

$sgModuleName = 'SovereignTrust.Foundation'
if (-not (Get-Module -Name $sgModuleName)) {
    $sgPath = Join-Path $PSScriptRoot "../../../../../SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1"
    Import-Module (Resolve-Path $sgPath).ProviderPath -Force
}

# Load all files (functions + classes)
. "$PSScriptRoot/Invoke-Session_ST.ps1"
#. "$PSScriptRoot/Invoke-Session_ST_GetNextPhaseSet.ps1"
#. "$PSScriptRoot/Invoke-SessionPhase.ps1"
. "$PSScriptRoot/Resolve-Function.ps1"

class Session_ST {
    [MappedSessionAdapter]$MappedAdapter
    [Signal]$Signal

    Session_ST() {
    }

    Session_ST([MappedSessionAdapter]$mappedAdapter) {
        $this.MappedAdapter = $mappedAdapter
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Session_ST") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct Session_ST — provided dictionary is null.")
            }

            $this.Signal = [Signal]::Start("Session_ST") | Select-Object -Last 1

            $jacket = [Signal]::Start("Session_ST") | Select-Object -Last 1 
            
            $this.Signal.SetJacket($jacket)
            $jacket.SetResult($dictionary)
            $opSignal.LogInformation("Session_ST constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing Session_ST: $_")
        }

        return $opSignal
    }

    #    [Signal] Invoke([string]$Slot, [Signal]$Context, [object]$Plan) {
    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$SessionSignal, [object]$Plan, [Signal]$ItemSignal) {
        #    [Signal] Invoke([string]$Slot, [Signal]$SessionSignal) {

        # Plan Config stores the path to place the ItemSignal 

        $opSignal = [Signal]::Start("Token_Environment.Invoke") | Select-Object -Last 1
        #        $conductor = $this.MappedAdapter.Signal.GetJacket()
        
        # TODO: Sessions need to store the plans they've ran in local cache (use depends on as the way to keep the hierarchy), keep list of the ones that have been ran and then, 
        # when a session goes to load, check the cache if it's already been loaded in the past and then re-run the set of plan steps. That way, if the server bails, it can reload (and session load balancing)
        # This will create seamless experience for the discord user to get sessions reloaded when there has been time in between sessions
        


        try {
            $resultSignal = Invoke-Session_ST -MappedAdapterSignal $this.Signal -Signal $SessionSignal -Slot $Slot -Activity $Activity -ItemSignal $ItemSignal -Plan $Plan | Select-Object -Last 1
            $opSignal.MergeSignal($resultSignal)

            if ($resultSignal.Success()) {
                $opSignal.SetResult($resultSignal.GetResult())
                $opSignal.LogInformation("✅ Ran successfully.")
            }
            else {
                $opSignal.LogWarning("Failed to Run.")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in Token_Environment.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }

}


function Resolve-Session_ST() {
    $object = [Session_ST]::new()
    return $object
}

# Export public utility functions
Export-ModuleMember -Function Resolve-Session_ST

