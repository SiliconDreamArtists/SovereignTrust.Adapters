$dependencyRoot = Join-Path $PSScriptRoot 'dependencies'
$inventoryPath = Join-Path $dependencyRoot 'inventory.json'
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    throw 'AzureSql packaged dependencies are missing. Run Package-AzureSql.ps1 during build and deploy the entire PowerShell module directory.'
}
if (-not $IsWindows -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64 -or [Environment]::Version.Major -lt 8) {
    throw 'AzureSql package requires Windows x64, PowerShell 7 on .NET 8 or later.'
}
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
if ($inventory.Package -ne 'Microsoft.Data.SqlClient' -or $inventory.Version -ne '6.1.7' -or
    $inventory.RuntimeIdentifier -ne 'win-x64' -or $inventory.TargetFramework -ne 'net8.0') {
    throw 'AzureSql dependency inventory does not match the pinned win-x64 package.'
}
foreach ($relativePath in $inventory.Files) {
    if (-not (Test-Path -LiteralPath (Join-Path $dependencyRoot $relativePath) -PathType Leaf)) {
        throw "AzureSql packaged dependency is missing: $relativePath. Rebuild and deploy the complete module artifact."
    }
}

$script:AzureSqlDependencyRoot = $dependencyRoot
$script:AzureSqlAssemblyResolver = [System.Func[System.Runtime.Loader.AssemblyLoadContext,System.Reflection.AssemblyName,System.Reflection.Assembly]] {
    param($context, $name)
    $candidate = Join-Path $script:AzureSqlDependencyRoot ($name.Name + '.dll')
    if (Test-Path -LiteralPath $candidate) { return $context.LoadFromAssemblyPath($candidate) }
    return $null
}
[System.Runtime.Loader.AssemblyLoadContext]::Default.add_Resolving($script:AzureSqlAssemblyResolver)
try {
    $providerPath = Join-Path $dependencyRoot 'Microsoft.Data.SqlClient.dll'
    $provider = [System.Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($providerPath)
    $null = $provider.GetType('Microsoft.Data.SqlClient.SqlConnection', $true)
    $null = $provider.GetType('Microsoft.Data.SqlClient.SqlConnectionStringBuilder', $true)
}
catch {
    [System.Runtime.Loader.AssemblyLoadContext]::Default.remove_Resolving($script:AzureSqlAssemblyResolver)
    throw "AzureSql packaged provider could not be loaded: $($_.Exception.Message)"
}
