function Invoke-AzureStorageAccount_ReadObject {
    param (
        [Signal]$Signal,
        [Parameter(Mandatory)][string]$VirtualPath,
        [Parameter()][string]$PathSuffix,
        [string]$SignalLevel = "Critical",
        [Parameter()][object]$Addresses
    )

    $opSignal = [Signal]::Start(
        "Invoke-AzureStorageAccount_ReadObject:$VirtualPath",
        $Signal
    ) | Select-Object -Last 1

    try {
        # ░▒▓█ NORMALIZE FILE EXTENSION █▓▒░
        if (
            $PathSuffix -and
            -not $VirtualPath.EndsWith(
                $PathSuffix,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            $VirtualPath = "$VirtualPath$PathSuffix"
        }

        # Azure blob paths always use forward slashes.
        $blobPath = $VirtualPath.Replace('\', '/').TrimStart('/')

        if ([string]::IsNullOrWhiteSpace($blobPath)) {
            return $opSignal.LogCritical(
                "Cannot read Azure blob because VirtualPath is empty."
            )
        }

        foreach ($address in @($Addresses)) {
            if ([string]::IsNullOrWhiteSpace([string]$address)) {
                continue
            }

            $hostAddress = ([string]$address).TrimEnd('/')
            $blobUri = "$hostAddress/$blobPath"

            $restPlan = [pscustomobject]@{
                Config = [pscustomobject]@{
                    Uri              = $blobUri
                    Host             = "https://storage.azure.com/"
                    Method           = "Get"
                    Headers          = @{
                        "x-ms-version" = "2023-11-03"
                    }
                    CacheAccessToken = $true
                }
            }

            $responseSignal = Invoke-MappedAdapter `
                -Adapter "Condenser.Rest" `
                -Activity "Get" `
                -Signal $Signal `
                -Plan $restPlan `
                -ItemSignal $Signal |
            Select-Object -Last 1

            if ($responseSignal.Success()) {
                $opSignal.MergeSignal($responseSignal)

                if ($responseSignal.HasResult()) {
                    $content = $responseSignal.GetResult($true)

                    $opSignal.SetResult($content)
                    $opSignal.LogInformation(
                        "📄 Found and read Azure blob: '$blobPath'"
                    )

                    return $opSignal
                }
            }

            # A failed request may simply mean that this address does
            # not contain the requested blob. Check the next address.
            $opSignal.MergeSignal($responseSignal)
        }

        $opSignal.LogMessage(
            $SignalLevel,
            "Blob '$blobPath' not found in any Azure Storage address."
        )
    }
    catch {
        $opSignal.LogCritical(
            "🔥 Exception during Invoke-AzureStorageAccount_ReadObject: $($_.Exception.Message)",
            $null,
            $_
        )
    }

    return $opSignal
}