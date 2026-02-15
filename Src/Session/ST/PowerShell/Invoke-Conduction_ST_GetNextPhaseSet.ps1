function Invoke-Conduction_ST_GetNextPhaseSet {
    [CmdletBinding()]
    param (
        # Current phase name (if null/empty, return "root" phases)
        [string]$DependsOn,

        # A Signal whose Result contains the flat phase array (or a wrapper holding it)
        [Parameter(Mandatory)]
        [Signal]$PhaseArraySignal,

        [Signal]$PhasesGridSignal
    )

    $opSignal = [Signal]::Start("Invoke-Conduction_ST_GetNextPhaseSet") | Select-Object -Last 1

    try {
        $phases = $PhaseArraySignal.GetResult()

        if ($null -eq $phases) {
            $opSignal.SetResult(@()) | Out-Null
            return $opSignal
        }

        # Force enumerable -> array
        $phases = @($phases)

        $dependsOnName = ($DependsOn ?? "").Trim()

        # Gather matches as objects with Name + Order, then sort, then return Name[].
        $matches = @()

        foreach ($phaseItem in $phases) {
            if ($null -eq $phaseItem) { continue }

            # Support wrapper form: { "Start-Listener": { ...phase... } }
            # If it's a dictionary with 1 key, unwrap to its value.
            $phase = $phaseItem
            if ($phaseItem -is [System.Collections.IDictionary] -and $phaseItem.Keys.Count -eq 1) {
                $onlyKey = @($phaseItem.Keys)[0]
                $phase   = $phaseItem[$onlyKey]
            }

            # Resolve Name
            $nameSignal = Resolve-PathFromDictionary -Dictionary $phase -Path "Name" -SignalLevel "Warning" | Select-Object -Last 1
            if (-not $nameSignal.HasResult()) { continue }
            $phaseName = ("{0}" -f $nameSignal.GetResult()).Trim()
            if ([string]::IsNullOrWhiteSpace($phaseName)) { continue }

            # Resolve Order (default to large number to push unordered to the end)
            $order = 999999
            $orderSignal = Resolve-PathFromDictionary -Dictionary $phase -Path "Order" -SignalLevel "Warning" | Select-Object -Last 1
            if ($orderSignal.HasResult()) {
                $rawOrder = $orderSignal.GetResult()
                # Robust numeric parse
                $tmp = 0
                if ([int]::TryParse(("{0}" -f $rawOrder), [ref]$tmp)) {
                    $order = $tmp
                }
            }

            # Resolve DependsOn (string, may contain comma list, "*" wildcard, or empty)
            $deps = @()
            $depSignal = Resolve-PathFromDictionary -Dictionary $phase -Path "DependsOn" -SignalLevel "Warning" | Select-Object -Last 1
            if ($depSignal.HasResult()) {
                $raw = $depSignal.GetResult()

                if ($raw -is [string]) {
                    $deps = $raw -split '\s*,\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                }
                elseif ($raw -is [System.Collections.IEnumerable]) {
                    $deps = @($raw) | ForEach-Object { ("{0}" -f $_).Trim() } | Where-Object { $_ -ne "" }
                }
            }

            # Matching rule:
            # - If DependsOnName is empty: return phases with empty DependsOn OR DependsOn contains "*"
            # - Else: return phases whose DependsOn contains the DependsOnName OR "*"
            $isMatch = $false
            if ([string]::IsNullOrWhiteSpace($dependsOnName)) {
                if (-not $deps.Count -or ($deps -contains "*")) { $isMatch = $true }
            } else {
                if (($deps -contains $dependsOnName) -or ($deps -contains "*")) { $isMatch = $true }
            }

            if ($isMatch) {
                $matches += [PSCustomObject]@{
                    Name  = $phaseName
                    Order = $order
                    Phase = $phase
                }
            }
        }

        $nextNames =
            $matches |
            Sort-Object -Property Order, Name |
            Select-Object -ExpandProperty Phase

            $nextPhasesSignals = @()
        foreach ($nextItem in $nextNames)
        {
            $nextName = $nextItem.Name
           $nextPhaseSignal = Resolve-PathFromDictionary -Dictionary $PhasesGridSignal -Path "@.@.#.$nextName" | Select-Object -Last 1
           $nextPhasesSignals += $nextPhaseSignal.GetResult()
        }

        $opSignal.SetResult(@($nextPhasesSignals)) | Out-Null
    }
    catch {
        $opSignal.LogCritical("Exception in Invoke-Conduction_ST_GetNextPhaseSet: $_") | Out-Null
    }

    return $opSignal
}
