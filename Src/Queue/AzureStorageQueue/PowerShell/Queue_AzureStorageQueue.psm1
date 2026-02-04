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

# ---- Load queue functions (your existing REST surface) ----
# Use your existing implementations here
# . "$PSScriptRoot/Read-StorageQueueApi.ps1"
# Optional if you have them:
# . "$PSScriptRoot/Delete-StorageQueueMessageApi.ps1"
# . "$PSScriptRoot/Update-StorageQueueVisibilityApi.ps1"
# . "$PSScriptRoot/Write-StorageQueueApi.ps1"

class Queue_AzureStorageQueue {
    [MappedQueueAdapter]$MappedAdapter
    [Signal]$Signal

    Queue_AzureStorageQueue() { }

    Queue_AzureStorageQueue([MappedQueueAdapter]$mappedAdapter) {
        $this.MappedAdapter = $mappedAdapter
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Queue_AzureStorageQueue.Construct") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                $opSignal.LogCritical("Cannot construct Queue_AzureStorageQueue — provided dictionary is null.")
                return $opSignal
            }

            $this.Signal = [Signal]::Start("Queue_AzureStorageQueue") | Select-Object -Last 1

            $jacket = [Signal]::Start("Queue_AzureStorageQueue.Jacket") | Select-Object -Last 1
            $jacket.SetResult($dictionary)

            $this.Signal.SetJacket($jacket)
            $opSignal.LogInformation("Queue_AzureStorageQueue constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing Queue_AzureStorageQueue: $_")
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
        $opSignal = [Signal]::Start("Queue_AzureStorageQueue.Invoke:$Slot.$Activity", $ItemSignal) | Select-Object -Last 1

        try {
            if (-not $ConductionSignal) {
                $opSignal.LogCritical("❌ Null ConductionSignal passed to Queue_AzureStorageQueue.Invoke()")
                return $opSignal
            }

            $opSignal.SetJacket($ConductionSignal)

            if (-not $Activity) {
                $opSignal.LogWarning("No Activity provided to Queue_AzureStorageQueue.Invoke()")
                return $opSignal
            }

            # Resolve Config from Plan (or from Environment if you prefer)
            # Convention: Plan contains everything needed to hit the service for this step
            $configSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config" -SignalLevel "Warning" | Select-Object -Last 1
            $config = $configSignal.HasResult() ? $configSignal.GetResult() : $null

            if (-not $config) {
                # Optional fallback: pull config from Environment/Jacket
                # $env = $ConductionSignal.GetJacket().GetResult()
                # $configSignal = Resolve-PathFromDictionary -Dictionary $env -Path "Queue.StorageQueue.Config" -SignalLevel "Warning" | Select-Object -Last 1
                $opSignal.LogWarning("StorageQueue Config not found on Plan.Config (no fallback enabled).")
            }

            $resultSignal = $null

            switch ($Activity) {

                # ---------------------------------------------------------
                # Canonical verbs
                # ---------------------------------------------------------

                "PeekBatch" {
                    return $this.Invoke($Slot, "ReadBatch", $ConductionSignal, $Plan, $ItemSignal)
                }

                "HandleMessage" {
                    $MessageTextSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.MessageText" | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($MessageTextSignal)) { return $opSignal }
                                $MessageText = $MessageTextSignal.GetResult()
                                $text = ([string]$MessageText).Trim()

                                # Try Base64→UTF8 (heuristic): re-encode equality ignoring trailing '=' padding
                                $decoded = $text
                                $wasBase64 = $false
                                try {
                                    $bytes = [Convert]::FromBase64String($text)
                                    $reencode = [Convert]::ToBase64String($bytes)
                                    if ($reencode.TrimEnd('=') -eq $text.Trim().TrimEnd('=')) {
                                        $decoded = [Text.Encoding]::UTF8.GetString($bytes)
                                        $wasBase64 = $true
                                    }
                                }
                                catch { }

                                # Undo HtmlEncode we do during Write-StorageQueueApi
                                $decoded = [System.Net.WebUtility]::HtmlDecode($decoded)

                                $MessageItem = $decoded | ConvertFrom-Json -Depth 10
                                # Run Item  Process

                                $DecodedItemSignal = [Signal]::Start("Queue_AzureStorageQueue.HandleItem.$($ItemSignal.Name)", $ItemSignal) | Select-Object -Last 1
                                $DecodedItemSignal.SetResult($MessageItem)


                                # Now delete Item
                                $deleteResultSignal = $this.Invoke($Slot, "AckItem", $ConductionSignal, $Plan, $ItemSignal)
                                $opSignal.MergeSignal($deleteResultSignal)

                    break
                }

                "ReadBatch" {
                    $PeekUntilEmptySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "PeekUntilEmpty" -Default $true | Select-Object -Last 1
                    $PeekUntilEmpty = [boolean]$PeekUntilEmptySignal.GetResult()

                    $peekDepthSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.PeekDepth" -Default 1 | Select-Object -Last 1
                    $peekDepth = [int]$peekDepthSignal.GetResult()

                    $VisibilitytimeoutSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Visibilitytimeout" -Default 10 | Select-Object -Last 1
                    $Visibilitytimeout = [int]$VisibilitytimeoutSignal.GetResult()


                    $MaxParallelismSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "MaxParallelism" -Default 1 | Select-Object -Last 1
                    $MaxParallelism = [int]$MaxParallelismSignal.GetResult()

                    $parallelSupport = $MaxParallelism -gt 1

                    $Dequeue = $true
                    $querystring = if ($Dequeue) {
                        "?numofmessages=$peekDepth&visibilitytimeout=$Visibilitytimeout"
                    }
                    else {
                        "?peekonly=true&numofmessages=$peekDepth"
                    }

                    $clonePlan = $Plan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
                    Add-PathToDictionary -Dictionary $clonePlan -Path "QueryString" -Value $querystring

                    $HostSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Addresses" | Select-Object -Last 1
                    $HostAddress = $HostSignal.GetResult()

                    $UriSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Resource" | Select-Object -Last 1
                    $Uri = $UriSignal.GetResult()

                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Uri" -Value "$HostAddress/$Uri"
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Host" -Value "$HostAddress"
                    $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.CacheAccessToken" -Value $true

                    $responseJacketSignal = [Signal]::Start("Queue_AzureStorageQueue.Invoke:$Slot.$Activity.Jacket", $ItemSignal) | Select-Object -Last 1

                    # Call Rest Endpoint
                    $responseSignal = Invoke-MappedAdapter -Adapter "Condenser.Rest" -Activity "Get" -Signal $ConductionSignal -Plan $clonePlan -ItemSignal $ItemSignal
                    if ($opSignal.MergeSignalAndVerifyFailure($responseSignal)) { return $opSignal }
                    $responseJacketSignal.SetJacket($responseSignal)
                    
                    # Format As Xml
                    $formatResultSignal = Invoke-CondenserAdapter -Slot "Format" -Activity "Xml" -Plan $Plan -Signal $ConductionSignal -ItemSignal $responseJacketSignal | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($formatResultSignal)) { return $opSignal }
                    $responseJacketSignal.SetJacket($formatResultSignal)

                    # Transform - Select Path to get Messages as array of strings
                    $transformResultSignal = Invoke-CondenserAdapter -Slot "Transform" -Activity "Select" -Plan $Plan -Signal $ConductionSignal -ItemSignal $responseJacketSignal | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($transformResultSignal)) { return $opSignal }
                    $responseJacketSignal.SetJacket($transformResultSignal)

                    # Set the result value from the rest endpoint
                    $opSignal.SetResult($responseJacketSignal.GetJacket().GetResult($true))

                    break
                }

                "WriteItem" {
                    # Plan should contain the payload to write
                    # e.g. Plan.MessageText or Plan.Payload etc.
                    # Placeholder: wire to your Write-StorageQueueApi when available.
                    $opSignal.LogWarning("WriteItem not implemented yet (wire to Write-StorageQueueApi).")
                    $resultSignal = [Signal]::Start("StorageQueue.WriteItem.Unresolved", $ItemSignal) | Select-Object -Last 1
                    break
                }

                "AckItem" {
                    # Ack = delete message. Needs MessageId + PopReceipt.
                    # Expect the message to be in ItemSignal jacket/result depending on your pipeline.

                    $MessageIdSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.MessageId" | Select-Object -Last 1
                    $PopReceiptSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.PopReceipt" | Select-Object -Last 1

                    $MessageId = $MessageIdSignal.GetResult()
                    $PopReceipt = $PopReceiptSignal.GetResult()
                    
                    # DELETE {ServiceUrl}/{MessageId}?popreceipt={PopReceipt}
                    $querystring = "/{0}?popreceipt={1}" -f $MessageId, [Uri]::EscapeDataString($PopReceipt)

                    try {
                        $clonePlan = $Plan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
                        Add-PathToDictionary -Dictionary $clonePlan -Path "QueryString" -Value $querystring

                        $HostSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Addresses" -Default 1 | Select-Object -Last 1
                        $HostAddress = $HostSignal.GetResult()

                        $UriSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Resource" -Default 1 | Select-Object -Last 1
                        $Uri = $UriSignal.GetResult()

                        $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Uri" -Value "$HostAddress/$Uri"
                        $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Host" -Value "$HostAddress"
                        $null = Add-PathToDictionary -Dictionary $clonePlan -Path "CacheAccessToken" -Value $true

                        $responseJacketSignal = [Signal]::Start("Queue_AzureStorageQueue.Invoke:$Slot.$Activity.Jacket", $ItemSignal) | Select-Object -Last 1

                        $responseSignal = Invoke-MappedAdapter -Adapter "Condenser.Rest" -Activity "Delete" -Signal $ConductionSignal -Plan $clonePlan -ItemSignal $ItemSignal
                        if ($opSignal.MergeSignalAndVerifyFailure($responseSignal)) { return $opSignal }
                    }
                    catch {
                        throw "Delete-StorageQueueApi: Failed to delete message id '$MessageId'. $($_.Exception.Message)"
                    }

                    $resultSignal = [Signal]::Start("StorageQueue.AckItem.Unresolved", $ItemSignal) | Select-Object -Last 1
                    break
                }

                "DeferItem" {
                    # Defer = update visibility timeout. Needs MessageId + PopReceipt + new Visibilitytimeout.
                    $msg = $ItemSignal.HasResult() ? $ItemSignal.GetResult() : $null

                    $visSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Visibilitytimeout" -Default 30 | Select-Object -Last 1
                    $vis = $visSignal.HasResult() ? [int]$visSignal.GetResult() : 30

                    if (-not $msg) {
                        $opSignal.LogWarning("DeferItem requires ItemSignal.Result to be the message object.")
                        $resultSignal = [Signal]::Start("StorageQueue.DeferItem.Unresolved", $ItemSignal) | Select-Object -Last 1
                        break
                    }

                    if (-not ($msg | Get-Member -Name "MessageId") -or -not ($msg | Get-Member -Name "PopReceipt")) {
                        $opSignal.LogWarning("DeferItem requires MessageId + PopReceipt on message.")
                        $resultSignal = [Signal]::Start("StorageQueue.DeferItem.Unresolved", $ItemSignal) | Select-Object -Last 1
                        break
                    }

                    # Placeholder: wire to your Update-StorageQueueVisibilityApi implementation
                    # $deferSignal = Update-StorageQueueVisibilityApi -Config $config -MessageId $msg.MessageId -PopReceipt $msg.PopReceipt -Visibilitytimeout $vis | Select-Object -Last 1
                    # $resultSignal = $deferSignal

                    $opSignal.LogWarning("DeferItem not implemented yet (wire to Update-StorageQueueVisibilityApi).")
                    $resultSignal = [Signal]::Start("StorageQueue.DeferItem.Unresolved", $ItemSignal) | Select-Object -Last 1
                    break
                }

                default {
                    $opSignal.LogWarning("Unsupported Activity: $Activity")
                    $resultSignal = [Signal]::Start("StorageQueue.UnsupportedActivity", $ItemSignal) | Select-Object -Last 1
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
            $opSignal.LogCritical("🔥 Exception in Queue_AzureStorageQueue.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }
}

function Resolve-Queue_AzureStorageQueue {
    $object = [Queue_AzureStorageQueue]::new()
    return $object
}

Export-ModuleMember -Function Resolve-Queue_AzureStorageQueue
