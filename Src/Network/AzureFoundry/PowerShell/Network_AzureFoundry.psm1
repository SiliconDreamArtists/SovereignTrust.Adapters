using module SignalGraph

$stModuleName = 'SovereignTrust.Foundation'
if (-not (Get-Module -Name $stModuleName)) {
    $stPath = Join-Path $PSScriptRoot "../../../../../SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1"
    Import-Module (Resolve-Path $stPath).ProviderPath -Force
}

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

                    # ░▒▓█ OPTIONAL PROMPT COMPONENTS █▓▒░

                    $systemSignal = Resolve-PathFromDictionary `
                        -Dictionary $Plan `
                        -Path "Config.Prompt.System" `
                        -SignalLevel "Information" |
                    Select-Object -Last 1

                    $textsSignal = Resolve-PathFromDictionary `
                        -Dictionary $Plan `
                        -Path "Config.Prompt.Texts" `
                        -SignalLevel "Information" |
                    Select-Object -Last 1

                    $mediaSignal = Resolve-PathFromDictionary `
                        -Dictionary $Plan `
                        -Path "Config.Prompt.Media" `
                        -SignalLevel "Information" |
                    Select-Object -Last 1


                    # ░▒▓█ BUILD MESSAGES █▓▒░

                    $messages = @()
                    # ─────────────────────────────────────────────
                    # SYSTEM
                    # Optional.
                    # Null / empty / whitespace means no system message.
                    # ─────────────────────────────────────────────

                    if ($systemSignal.HasResult()) {
                        $systemContent = $systemSignal.GetResult()
                        if (
                            $null -ne $systemContent -and
                            -not [string]::IsNullOrWhiteSpace([string]$systemContent)
                        ) {
                            $messages += @{
                                role    = "system"
                                content = [string]$systemContent
                            }
                        }
                    }

                    # ─────────────────────────────────────────────
                    # USER CONTENT PARTS
                    #
                    # Texts and Media both become content items
                    # inside one user message.
                    # ─────────────────────────────────────────────

                    $userContent = @()

                    # ░▒▓█ TEXTS █▓▒░
                    if ($textsSignal.HasResult()) {
                        $texts = $textsSignal.GetResult()
                        if ($null -ne $texts) {
                            foreach ($text in @($texts)) {
                                if (
                                    $null -eq $text -or
                                    [string]::IsNullOrWhiteSpace([string]$text)
                                ) {
                                    continue
                                }

                                $userContent += @{
                                    type = "text"
                                    text = [string]$text
                                }
                            }
                        }
                    }


                    # ░▒▓█ MEDIA █▓▒░
                    if ($mediaSignal.HasResult()) {
                        $mediaItems = $mediaSignal.GetResult()
                        if ($null -ne $mediaItems) {
                            foreach ($mediaItem in @($mediaItems)) {
                                if ($null -eq $mediaItem) {
                                    continue
                                }

                                # ─────────────────────────────────
                                # Resolve optional media properties
                                # ─────────────────────────────────

                                $mediaPath = $null
                                $mediaUrl = $null
                                $mediaType = "image"
                                $detail = "high"

                                if ($mediaItem -is [System.Collections.IDictionary]) {
                                    if ($mediaItem.Contains("MediaPath")) {
                                        $mediaPath = $mediaItem["MediaPath"]
                                    }

                                    if ($mediaItem.Contains("MediaUrl")) {
                                        $mediaUrl = $mediaItem["MediaUrl"]
                                    }

                                    if ($mediaItem.Contains("MediaType")) {
                                        $mediaType = $mediaItem["MediaType"]
                                    }

                                    if ($mediaItem.Contains("Detail")) {
                                        $detail = $mediaItem["Detail"]
                                    }
                                }
                                else {
                                    if ($mediaItem.PSObject.Properties["MediaPath"]) {
                                        $mediaPath = $mediaItem.MediaPath
                                    }

                                    if ($mediaItem.PSObject.Properties["MediaUrl"]) {
                                        $mediaUrl = $mediaItem.MediaUrl
                                    }

                                    if ($mediaItem.PSObject.Properties["MediaType"]) {
                                        $mediaType = $mediaItem.MediaType
                                    }

                                    if ($mediaItem.PSObject.Properties["Detail"]) {
                                        $detail = $mediaItem.Detail
                                    }
                                }

                                # Nothing usable in this media entry.
                                if (
                                    [string]::IsNullOrWhiteSpace([string]$mediaPath) -and
                                    [string]::IsNullOrWhiteSpace([string]$mediaUrl)
                                ) {
                                    continue
                                }

                                # Current adapter implementation supports images.
                                if ([string]::IsNullOrWhiteSpace([string]$mediaType)) {
                                    $mediaType = "image"
                                }

                                $mediaType = ([string]$mediaType).ToLowerInvariant()

                                if ($mediaType -ne "image") {
                                    throw "Unsupported media type: $mediaType"
                                }

                                # ─────────────────────────────────
                                # URL media
                                # ─────────────────────────────────

                                if (-not [string]::IsNullOrWhiteSpace([string]$mediaUrl)) {

                                    $mediaDataUrl = [string]$mediaUrl
                                }

                                # ─────────────────────────────────
                                # Local media
                                # ─────────────────────────────────

                                else {
                                    $mediaPath = [string]$mediaPath
                                    $mediaExtension =
                                    [System.IO.Path]::GetExtension($mediaPath).ToLowerInvariant()

                                    $mimeType = switch ($mediaExtension) {
                                        ".jpg" { "image/jpeg" }
                                        ".jpeg" { "image/jpeg" }
                                        ".png" { "image/png" }
                                        ".webp" { "image/webp" }
                                        ".gif" { "image/gif" }

                                        default {
                                            throw "Unsupported image format: $mediaExtension"
                                        }
                                    }

                                    $mediaBytes =
                                    [System.IO.File]::ReadAllBytes($mediaPath)

                                    $mediaBase64 =
                                    [Convert]::ToBase64String($mediaBytes)

                                    $mediaDataUrl =
                                    "data:$mimeType;base64,$mediaBase64"
                                }


                                # ─────────────────────────────────
                                # Add image content part
                                # ─────────────────────────────────

                                $userContent += @{
                                    type      = "image_url"
                                    image_url = @{
                                        url    = $mediaDataUrl
                                        detail = $detail
                                    }
                                }
                            }
                        }
                    }

                    # ░▒▓█ CREATE USER MESSAGE IF CONTENT EXISTS █▓▒░
                    if ($userContent.Count -gt 0) {
                        $messages += @{
                            role    = "user"
                            content = $userContent
                        }
                    }


                    # ░▒▓█ REQUIRE AT LEAST SOME USABLE PROMPT CONTENT █▓▒░
                    if ($messages.Count -eq 0) {
                        throw "AI Prompt contains no usable System, Texts, or Media content."
                    }

                    # ░▒▓█ REQUEST BODY █▓▒░
                    $body = [PSCustomObject]@{
                        messages              = $messages
                        max_completion_tokens = 13107
                        temperature           = 1
                        top_p                 = 1
                        frequency_penalty     = 0
                        presence_penalty      = 0
                        model                 = "gpt-5"
                    }

                    # ░▒▓█ SEND REQUEST █▓▒░
                    $clonePlan =
                    (Resolve-ClonePlan -Plan $Plan |
                    Select-Object -Last 1).GetResult()

                    $HostSignal =
                    Resolve-PathFromDictionary `
                        -Dictionary $this.Signal `
                        -Path "%.@.Addresses" |
                    Select-Object -Last 1

                    $HostAddress = $HostSignal.GetResult()

                    $ResourceSignal =
                    Resolve-PathFromDictionary `
                        -Dictionary $this.Signal `
                        -Path "%.@.Resource" |
                    Select-Object -Last 1

                    $resource = $ResourceSignal.GetResult()

                    $headers = @{
                        "Content-Type"  = "application/json"
                        "Authorization" = "Bearer $resource"
                    }

                    $null = Add-PathToDictionary `
                        -Dictionary $clonePlan `
                        -Path "Config.Method" `
                        -Value "Post"

                    $null = Add-PathToDictionary `
                        -Dictionary $clonePlan `
                        -Path "Config.Host" `
                        -Value "$HostAddress"

                    $null = Add-PathToDictionary `
                        -Dictionary $clonePlan `
                        -Path "Config.CacheAccessToken" `
                        -Value $true

                    $null = Add-PathToDictionary `
                        -Dictionary $clonePlan `
                        -Path "Config.SkipBearerToken" `
                        -Value $true

                    $null = Add-PathToDictionary `
                        -Dictionary $clonePlan `
                        -Path "Config.Body" `
                        -Value $body

                    $null = Add-PathToDictionary `
                        -Dictionary $clonePlan `
                        -Path "Config.Headers" `
                        -Value $headers

                    $null = Add-PathToDictionary `
                        -Dictionary $clonePlan `
                        -Path "Config.Uri" `
                        -Value "$HostAddress"

                    $responseSignal =
                    Invoke-MappedAdapter `
                        -Adapter "Condenser.Rest" `
                        -Activity "POST" `
                        -Signal $ConductionSignal `
                        -Plan $clonePlan `
                        -ItemSignal $ItemSignal

                    $opSignal.SetResult($responseSignal.GetResult())

                    break
                }
                "SendMessageOriginal" {
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Content" | Select-Object -Last 1
                    $mediaPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.MediaPath" -SignalLevel "Information" | Select-Object -Last 1
                    $mediaUrlSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.MediaUrl" -SignalLevel "Information" | Select-Object -Last 1

                    if (($mediaPathSignal.HasResult() -and $mediaPathSignal.GetResult() -ne "") -or ($mediaUrlSignal.HasResult() -and $mediaUrlSignal.GetResult() -ne "")) {
                        $mediaTypeSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.MediaType" -Default "image" | Select-Object -Last 1
                        $mediaPath = $mediaPathSignal.HasResult() ? $mediaPathSignal.GetResult() : $mediaUrlSignal.GetResult()
                        $isUrl = $mediaUrlSignal.HasResult()
                        $mediaExtension = [System.IO.Path]::GetExtension($mediaPath).ToLowerInvariant()
                        $mediaType = $mediaTypeSignal.GetResult()

                        $mimeType = switch ($mediaExtension) {
                            ".jpg" { "image/jpeg" }
                            ".jpeg" { "image/jpeg" }
                            ".png" { "image/png" }
                            ".webp" { "image/webp" }
                            ".gif" { "image/gif" }
                            default {
                                throw "Unsupported image format: $mediaExtension"
                            }
                        }

                        # Convert the local image into a Base64 data URL.                        
                        if ($isUrl) {
                            $mediaDataUrl = $mediaPath
                        }
                        else {
                            $mediaBytes = [System.IO.File]::ReadAllBytes($mediaPath)
                            $mediaBase64 = [Convert]::ToBase64String($mediaBytes)
                            $mediaDataUrl = "data:$mimeType;base64,$mediaBase64"
                        }
                        $messages = @(
                            @{
                                role    = "user"
                                content = @(
                                    @{
                                        type = "text"
                                        text = $contentSignal.GetResult()
                                    },
                                    @{
                                        type      = "$($mediaType)_url"
                                        image_url = @{
                                            url    = $mediaDataUrl
                                            detail = "high"
                                        }
                                    }
                                )
                            }
                        )

                    }
                    else {
                        $messages = @(
                            @{
                                role    = 'user'
                                content = $contentSignal.GetResult()
                            }
                        )
                    }

                    $body = [PSCustomObject]@{
                        messages              = $messages
                        max_completion_tokens = 13107
                        temperature           = 1
                        top_p                 = 1
                        frequency_penalty     = 0
                        presence_penalty      = 0
                        model                 = 'gpt-5'
                    }

                    $clonePlan = (Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1).GetResult()
                    $HostSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Addresses" | Select-Object -Last 1
                    $HostAddress = $HostSignal.GetResult()

                    $ResourceSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path "%.@.Resource" | Select-Object -Last 1
                    $resource = $ResourceSignal.GetResult()

                    $headers = @{
                        "Content-Type"  = "application/json"
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
                    $MessageSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $Plan.Path | Select-Object -Last 1

                    # TODO: Review if we should keep format inside of the Memory Condenser
                    $FormatSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Format" -SignalLevel "Warning" | Select-Object -Last 1
                    $Format = $FormatSignal.HasResult()    ? $FormatSignal.GetResult()    : $null
                    if ($Format) {
                        $FormatSignal = [Signal]::Start("MemoryCondenser.Invoke.Format", $ItemSignal) | Select-Object -Last 1
                        $FormatSignal.SetJacket($MessageSignal)
                        $FormatSignal.SetPointer($ItemSignal.GetPointer())

                        $StepResultSignal = Invoke-CondenserAdapter -Slot "Format" -Activity $Format -Plan $Plan -Signal $ConductionSignal -ItemSignal $FormatSignal | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure($StepResultSignal)) { return $opSignal }
                        $MessageSignal.SetResult($StepResultSignal.GetResult())
                    }

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
                }
                else {
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
