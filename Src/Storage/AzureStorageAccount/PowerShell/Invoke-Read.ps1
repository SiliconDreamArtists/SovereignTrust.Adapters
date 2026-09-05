# =============================================================================
# ▶️ Start-STCSessionHost.ps1
#  Entrypoint wrapper for launching SDA Bonding Conductor SessionHost runtime
# =============================================================================

function Start-STCSessionHost {
    [CmdletBinding()]
    param (
        [string]$SessionName     = "DefaultSession",
        [string]$EnvironmentPath = "/SDA/fusion.json",
        [bool]$RunInline             = $false
    )

    $opSignal = [Signal]::Start("Start-STCSessionHost:$SessionName")

    $scriptPath = Join-Path $PSScriptRoot "SessionHost.ps1"

    if (-not (Test-Path $scriptPath)) {
        $opSignal.LogCritical("❌ Could not find SessionHost.ps1 at: $scriptPath")
        return $opSignal
    }

    if ($RunInline) {
        $opSignal.LogInformation("🛠️ Debug mode enabled: running inline")
        $inlineSig = & $scriptPath -SessionName $SessionName -EnvironmentPath $EnvironmentPath | Select-Object -Last 1
        if ($inlineSig -and $inlineSig.Failure()) {
            $opSignal.MergeSignal($inlineSig)
            return $opSignal
        }
        $opSignal.SetResult($inlineSig?.GetResult())
    }
    else {
        $hostSig = Start-PwshSessionHost -SessionName $SessionName -ScriptPath $scriptPath -RunInline $RunInline | Select-Object -Last 1
        if ($hostSig.Failure()) {
            $opSignal.MergeSignal($hostSig)
            return $opSignal
        }
        $opSignal.SetResult($hostSig.GetResult())
    }

    $opSignal.LogInformation("✅ Bonding Conductor SessionHost '$SessionName' completed (Debug: $RunInline).")
    return $opSignal
}
