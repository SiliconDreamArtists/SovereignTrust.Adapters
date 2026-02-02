function Resolve-Function {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Function,
        [bool]$ThrowOnMissing = $true
    )

    $opSignal = [Signal]::Start("Resolve-FunctionLoaded") | Select-Object -Last 1

    try {
        # If Function contains dots, keep only the last segment
        if ($Function -like '*.*') {
            $Function = $Function.Substring($Function.LastIndexOf('.') + 1)
        }

        $cmd = Get-Command -Name $Function -ErrorAction SilentlyContinue

        if ($cmd) {
            $opSignal.SetResult($cmd)
            return $opSignal
        }

        $msg = "Function '$Function' is not loaded."

        if ($ThrowOnMissing) {
            $opSignal.LogCritical("❌ $msg")
        } else {
            $opSignal.LogWarning("⚠️ $msg")
        }

        return $opSignal
    }
    catch {
        $opSignal.LogCritical("💥 Exception in Resolve-FunctionLoaded: $($_.Exception.Message)", $null, $_)
        return $opSignal
    }
}
