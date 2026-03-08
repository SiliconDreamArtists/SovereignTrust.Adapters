. "$PSScriptRoot\..\..\..\..\..\SignalGraph\Src\PowerShell\Classes\SignalEntry.ps1"
. "$PSScriptRoot\..\..\..\..\..\SignalGraph\Src\PowerShell\Classes\Signal.ps1"
. "$PSScriptRoot\..\..\..\..\..\SignalGraph\Src\PowerShell\Classes\Graph.ps1"

$sgModuleName = 'SignalGraph'
if (-not (Get-Module -Name $sgModuleName)) {
    $sgPath = Join-Path $PSScriptRoot "../../../../../SignalGraph/Src/PowerShell/SignalGraph.psd1"
    Import-Module (Resolve-Path $sgPath).ProviderPath -Force
}

$stModuleName = 'SovereignTrust.Foundation'
if (-not (Get-Module -Name $stModuleName)) {
    $stPath = Join-Path $PSScriptRoot "../../../../../SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1"
    Import-Module (Resolve-Path $stPath).ProviderPath -Force
}

# ---- Load Network functions (your existing REST surface) ----
# Use your existing implementations here
# . "$PSScriptRoot/Read-StorageNetworkApi.ps1"
# Optional if you have them:
# . "$PSScriptRoot/Delete-StorageNetworkMessageApi.ps1"
# . "$PSScriptRoot/Update-StorageNetworkVisibilityApi.ps1"
# . "$PSScriptRoot/Write-StorageNetworkApi.ps1"

class Network_AzureFoundry {
    [MappedNetworkAdapter]$MappedAdapter
    [Signal]$Signal

    Network_AzureFoundry() { }

    Network_AzureFoundry([MappedNetworkAdapter]$mappedAdapter) {
        $this.MappedAdapter = $mappedAdapter
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Network_AzureFoundry.Construct") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                $opSignal.LogCritical("Cannot construct Network_AzureFoundry — provided dictionary is null.")
                return $opSignal
            }

            $this.Signal = [Signal]::Start("Network_AzureFoundry") | Select-Object -Last 1

            $jacket = [Signal]::Start("Network_AzureFoundry.Jacket") | Select-Object -Last 1
            $jacket.SetResult($dictionary)

            $this.Signal.SetJacket($jacket)
            $opSignal.LogInformation("Network_AzureFoundry constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing Network_AzureFoundry: $_")
        }

        return $opSignal
    }

    # ---------------------------------------------------------------------
    # Universal Invoke entry 
    # Activity uses canonical verb set: ReadBatch, PeekBatch, AckItem, DeferItem, WriteItem
    # ---------------------------------------------------------------------
    [Signal] Invoke(
        [string]$Slot,
        [string]$Activity,
        [Signal]$ConductionSignal,
        [object]$Plan,
        [Signal]$ItemSignal
    ) {
        $opSignal = [Signal]::Start("Network_AzureFoundry.Invoke:$Slot.$Activity", $ConductionSignal) | Select-Object -Last 1

        try {
            if (-not $ConductionSignal) {
                $opSignal.LogCritical("Null ConductionSignal passed to Network_AzureFoundry.Invoke()")
                return $opSignal
            }

            if (-not $Activity) {
                $opSignal.LogWarning("No Activity provided to Network_AzureFoundry.Invoke()")
                return $opSignal
            }

            # Resolve Config from Plan (or from Environment if you prefer)
            # Convention: Plan contains everything needed to hit the service for this step
            $configSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config" -SignalLevel "Warning" | Select-Object -Last 1
            $config = $configSignal.HasResult() ? $configSignal.GetResult() : $null

            if (-not $config) {
                # Optional fallback: pull config from Environment/Jacket
                # $env = $ConductionSignal.GetJacket().GetResult()
                # $configSignal = Resolve-PathFromDictionary -Dictionary $env -Path "Network.StorageNetwork.Config" -SignalLevel "Warning" | Select-Object -Last 1
                $opSignal.LogWarning("StorageNetwork Config not found on Plan.Config (no fallback enabled).")
            }

            $resultSignal = $null

            switch ($Activity) {
                "SendMessage" {
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Content" | Select-Object -Last 1
                    $messages = @(
                        @{
                            role = 'user'
                            content = $contentSignal.GetResult()
                        }
                    )
                    $body = [PSCustomObject]@{
                        messages = $messages
                        max_completion_tokens = 13107
                        temperature = 1
                        top_p = 1
                        frequency_penalty = 0
                        presence_penalty = 0
                        model = 'gpt-4.1'
                    }

                    $clonePlan = (Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1).GetResult()
                    $HostSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Addresses" | Select-Object -Last 1
                    $HostAddress = $HostSignal.GetResult()

                    $ResourceSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Resource" | Select-Object -Last 1
                    $resource = $ResourceSignal.GetResult()

                    $headers = @{
                        "Content-Type" = "application/json"
                        "Authorization" = "Bearer $resource"
                    }

                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Method" -Value "Post"
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Host" -Value "$HostAddress"
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.CacheAccessToken" -Value $true
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.SkipBearerToken" -Value $true
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Body" -Value $body
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Headers" -Value $headers
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Uri" -Value "$HostAddress"
                    
                    $responseSignal = Invoke-MappedAdapter -Adapter "Condenser.Rest" -Activity "POST" -Signal $ConductionSignal -Plan $clonePlan -ItemSignal $ItemSignal
                    $opSignal.SetResult($responseSignal.GetResult())
                    break   
                }

                "HandleMessage" {
                    # TODO: Review, this is being done in this class, but it's generic enough it should be somewhere else.
#                    $MessageSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Message" | Select-Object -Last 1
                    $MessageSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $Plan.Path | Select-Object -Last 1
                    if ($MessageSignal.HasResult()) {
                        $opSignal.SetResult($MessageSignal.GetResult())
                    }
                  break   
                }
                default {
                    $opSignal.LogWarning("Unsupported Activity: $Activity")
                    $resultSignal = [Signal]::Start("StorageNetwork.UnsupportedActivity", $ItemSignal) | Select-Object -Last 1
                    break
                }
            }

            if ($resultSignal) {
                $opSignal.MergeSignal($resultSignal)
                if ($resultSignal.Success()) {
                    $opSignal.SetResult($resultSignal.GetResult($true))
                    $opSignal.LogInformation("✅ $Slot.$Activity succeeded.")
                } else {
                    $opSignal.LogWarning("$Slot.$Activity did not succeed.")
                }
            }

        }
        catch {
            $opSignal.LogCritical("🔥 Exception in Network_AzureFoundry.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }
}

function Resolve-Network_AzureFoundry {
    $object = [Network_AzureFoundry]::new()
    return $object
}

Export-ModuleMember -Function Resolve-Network_AzureFoundry
