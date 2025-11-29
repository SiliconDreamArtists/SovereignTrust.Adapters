# Load all files (functions + classes)
. "$PSScriptRoot/Invoke-Network_AzureStorageQueue.ps1"



class Network_AzureStorageQueue {
    [MappedConductionAdapter]$MappedAdapter
    [Signal]$Signal

    Conduction_SDA() {
    }

    Conduction_SDA([MappedConductionAdapter]$mappedAdapter) {
        $this.MappedAdapter = $mappedAdapter
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Conduction_SDA") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct Conduction_SDA — provided dictionary is null.")
            }

            $this.Signal = [Signal]::Start("Conduction_SDA") | Select-Object -Last 1

            $jacket = [Signal]::Start("Conduction_SDA") | Select-Object -Last 1 
            
            $this.Signal.SetJacket($jacket)
            $jacket.SetResult($dictionary)
            $opSignal.LogInformation("Conduction_SDA constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing Conduction_SDA: $_")
        }

        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [Signal]$Context, [object]$Plan) {
        $opSignal = [Signal]::Start("Token_Environment.Invoke") | Select-Object -Last 1
        $conductor = $this.MappedAdapter.Signal.GetJacket()
        
        try {
            $resultSignal = Invoke-Network_AzureStorageQueue -Conductor $conductor -Conduit $null -ConductionSignal $Context | Select-Object -Last 1
            $opSignal.MergeSignal($resultSignal)

            if ($resultSignal.Success()) {
                $opSignal.SetResult($resultSignal.GetResult())
                $opSignal.LogInformation("✅ Ran successfully.")
            } else {
                $opSignal.LogWarning("⚠️ Failed to Run.")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in Token_Environment.Invoke: $($_.Exception.Message)")
        }

        return $opSignal
    }
}


function Resolve-Network_AzureStorageQueue()
{
    $object = [Network_AzureStorageQueue]::new()
    return $object
}


# Export public utility functions
Export-ModuleMember -Function Resolve-Network_AzureStorageQueue
