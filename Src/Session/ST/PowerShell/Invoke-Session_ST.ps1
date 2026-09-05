function Invoke-Session_ST {
    param (
        [Signal]$MappedAdapterSignal,
        [Signal]$Signal,
        [string]$Slot,
        [string]$Activity,  
        [object]$Plan,
        [Signal]$ItemSignal
    )

    $opSignal = [Signal]::Start("Session_ST:$($Plan.Name)") | Select-Object -Last 1

    $sessionSignal = Resolve-PathFromDictionary -Dictionary $MappedAdapterSignal -Path $Plan.Path -SignalLevel "Information" | Select-Object -Last 1
    $opSignal.MergeSignal($sessionSignal)
    
    if ($sessionSignal.HasResult()) {
        $opSignal.SetResult($sessionSignal.GetResult())
    } else {
#        $sessionSignal = [Signal]::Start("Session_ST:$($Plan.Name)") | Select-Object -Last 1
#        $sessionSignal.SetResult($ItemSignal)
        $addSignal = Add-PathToDictionary -Dictionary $MappedAdapterSignal -Path $Plan.Path -Value $ItemSignal.GetJacket() | Select-Object -Last 1
        $opSignal.MergeSignal($addSignal)
        $opSignal.SetResult($ItemSignal.GetJacket())
    }

    return $opSignal
}
