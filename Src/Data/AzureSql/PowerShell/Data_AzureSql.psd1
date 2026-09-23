@{
    RootModule = 'Data_AzureSql.psm1'
    ModuleVersion = '1.0.0'
    CompatiblePSEditions = @('Core')
    GUID = '64270e37-29cb-47be-887f-62488436e69e'
    Author = 'Silicon Dream Artists'
    CompanyName = 'Silicon Dream Artists'
    Copyright = '(c) Silicon Dream Artists. All rights reserved.'
    Description = 'Azure SQL data adapter module. SQL execution is pending implementation.'
    PowerShellVersion = '7.0'
    RequiredModules = @('SignalGraph')
    FunctionsToExport = @('Resolve-Data_AzureSql', 'ConvertTo-AzureSqlJsonResult')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{ PSData = @{
        Tags = @('Data_AzureSql', 'SovereignTrust', 'Adapters', 'AzureSql')
        LicenseUri = 'https://opensource.org/licenses/MIT'
        ProjectUri = 'https://github.com/SiliconDreamArtists/SovereignTrust.Adapters'
    } }
}
