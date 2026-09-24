function New-AzureSqlConnectionBuilder {
    param([object]$Adapter)

    $resource = Get-AzureSqlObjectValue (Get-AzureSqlObjectValue $Adapter 'Configuration') 'Resource'
    if ($resource -isnot [string] -or [string]::IsNullOrWhiteSpace($resource)) {
        throw 'Azure SQL requires a hydrated connection resource.'
    }

    try {
        $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($resource)
    }
    catch {
        # SqlClient parse errors can quote the supplied resource. Never forward them.
        throw 'Azure SQL connection resource is invalid.'
    }

    if ([string]::IsNullOrWhiteSpace($builder.DataSource) -or
        [string]::IsNullOrWhiteSpace($builder.InitialCatalog) -or
        $builder.DataSource -match '^https?://') {
        throw 'Azure SQL connection resource requires a SQL data source and initial catalog.'
    }
    $authentication = [string]$builder.Authentication
    if ($authentication -notin @('ActiveDirectoryDefault', 'ActiveDirectoryManagedIdentity')) {
        throw 'Azure SQL connection resource has an unsupported authentication mode.'
    }
    if ($builder.TrustServerCertificate -or [string]$builder.Encrypt -in @('False', 'Optional') -or
        $builder.IntegratedSecurity -or -not [string]::IsNullOrEmpty($builder.Password)) {
        throw 'Azure SQL connection resource contains an insecure or incompatible setting.'
    }
    if ($authentication -eq 'ActiveDirectoryDefault' -and -not [string]::IsNullOrEmpty($builder.UserID)) {
        throw 'Azure SQL Default authentication does not accept User ID.'
    }
    if ($builder.ConnectTimeout -lt 1 -or $builder.ConnectTimeout -gt 300) {
        throw 'Azure SQL connection timeout must be between 1 and 300 seconds.'
    }

    $builder.Encrypt = $true
    $builder.TrustServerCertificate = $false
    $builder.PersistSecurityInfo = $false
    $builder['Application Name'] = 'SovereignTrust.Adapters.Data.AzureSql'
    return $builder
}
