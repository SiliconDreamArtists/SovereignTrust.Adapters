using module SignalGraph

$foundationModuleName = 'SovereignTrust.Foundation'
if (-not (Get-Module -Name $foundationModuleName)) {
    $foundationPath = Join-Path $PSScriptRoot '../../../../../SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1'
    Import-Module (Resolve-Path $foundationPath).ProviderPath -Force
}

. "$PSScriptRoot/ConvertTo-AzureSqlJsonResult.ps1"
. "$PSScriptRoot/Invoke-Data_AzureSql.ps1"
. "$PSScriptRoot/Data_AzureSql.ps1"

Export-ModuleMember -Function Resolve-Data_AzureSql, ConvertTo-AzureSqlJsonResult
