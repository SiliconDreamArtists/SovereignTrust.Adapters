class Storage_AzureKeyVault {
    [MappedStorageAdapter]$MappedAdapter
    [object]$Jacket

    Storage_AzureKeyVault() {
    }

    Storage_AzureKeyVault([MappedStorageAdapter]$mappedAdapter) {
        $this.MappedAdapter = $mappedAdapter
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-EmbeddedFileSystem") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct EmbeddedFileSystem — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("EmbeddedFileSystem constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing EmbeddedFileSystem: $_")
        }

        return $opSignal
    }

    [Signal] ReadObjectAsJson([string]$virtualPath) {
        $opSignal = [Signal]::Start("EmbeddedFileSystem.ReadObjectAsJson") | Select-Object -Last 1

        try {
            # 🧠 Ensure the virtual path ends with '.json'
            if (-not $virtualPath.ToLower().EndsWith(".json")) {
                $virtualPath = "$virtualPath.json"
            }

            # 🔁 Read raw content using internal ReadObject
            $rawSignal = $this.ReadObject($virtualPath) | Select-Object -Last 1
            $opSignal.MergeSignal($rawSignal)

            if ($rawSignal.Success()) {
                $jsonText = $rawSignal.GetResult()
                $parsed = $null

                try {
                    $parsed = $jsonText | ConvertFrom-Json -Depth 20
                }
                catch {
                    return $opSignal.LogCritical("❌ Failed to parse JSON content: $($_.Exception.Message)")
                }

                $opSignal.SetResult($parsed)
                $opSignal.LogInformation("📄 JSON content parsed successfully from: $virtualPath")
            }
            else {
                $opSignal.LogWarning("⚠️ No raw content found at: $virtualPath")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in EmbeddedFileSystem.ReadObjectAsJson: $($_.Exception.Message)")
        }

        return $opSignal
    }

    [Signal] ReadObject([string]$virtualPath) {
        $opSignal = [Signal]::Start("EmbeddedFileSystem.ReadObject") | Select-Object -Last 1

        try {
            # ░▒▓█ RESOLVE ADDRESSES FROM %.@.Addresses █▓▒░
            $addressSignal = Resolve-PathFromDictionary -Dictionary $this -Path '%.@.Addresses' | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($addressSignal))) {
                return $opSignal.LogCritical("❌ Could not resolve Jacket.Addresses path.")
            }

            $addresses = $addressSignal.GetResult()
            $pathWithExtension = "$virtualPath.json"

            foreach ($address in $addresses) {
                $fullPath = Join-Path -Path $address -ChildPath $pathWithExtension

                if (Test-Path -Path $fullPath) {
                    $content = Get-Content -Path $fullPath -Raw
                    $opSignal.SetResult($content)
                    $opSignal.LogInformation("📄 Found and read file: $fullPath")
                    return $opSignal
                }
            }

            $opSignal.LogWarning("⚠️ File '$pathWithExtension' not found in any address.")
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in EmbeddedFileSystem.ReadObject: $($_.Exception.Message)")
        }

        return $opSignal
    }
}
