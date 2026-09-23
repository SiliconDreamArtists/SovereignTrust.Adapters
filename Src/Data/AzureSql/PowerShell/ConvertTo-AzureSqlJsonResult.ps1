function Get-AzureSqlObjectValue {
    param([object]$InputObject, [string]$Name, [object]$Default = $null)
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject.Contains($Name) ? $InputObject[$Name] : $Default
    }
    $property = $InputObject.PSObject.Properties[$Name]
    return $null -ne $property ? $property.Value : $Default
}

function Test-AzureSqlObjectMember {
    param([object]$InputObject, [string]$Name)
    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject.Contains($Name) }
    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function Get-AzureSqlTypeName {
    param([Type]$Type)
    if ($null -eq $Type) { return 'nvarchar' }
    switch ($Type.FullName) {
        'System.Int16' { 'smallint'; break }
        'System.Int32' { 'int'; break }
        'System.Int64' { 'bigint'; break }
        'System.UInt16' { 'int'; break }
        'System.UInt32' { 'bigint'; break }
        'System.UInt64' { 'decimal'; break }
        'System.Boolean' { 'bit'; break }
        'System.Byte' { 'tinyint'; break }
        'System.Decimal' { 'decimal'; break }
        'System.Double' { 'float'; break }
        'System.Single' { 'real'; break }
        'System.DateTime' { 'datetime2'; break }
        'System.DateTimeOffset' { 'datetimeoffset'; break }
        'System.Guid' { 'uniqueidentifier'; break }
        'System.Byte[]' { 'varbinary'; break }
        default { 'nvarchar' }
    }
}

function ConvertTo-AzureSqlJsonValue {
    param([object]$Value)
    if ($null -eq $Value -or $Value -is [DBNull]) { return $null }
    if ($Value -is [byte[]]) { return [Convert]::ToBase64String($Value) }
    if ($Value -is [datetime]) {
        $utcValue = if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
            [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)
        }
        else {
            $Value.ToUniversalTime()
        }
        return $utcValue.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [decimal] -or $Value -is [System.Numerics.BigInteger] -or $Value -is [uint64]) {
        return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [long] -and ([Math]::Abs([decimal]$Value) -gt 9007199254740991)) {
        return $Value.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [guid] -or $Value -is [timespan]) { return [string]$Value }
    if ($Value -is [double] -and ([double]::IsNaN($Value) -or [double]::IsInfinity($Value))) { return [string]$Value }
    if ($Value -is [single] -and ([single]::IsNaN($Value) -or [single]::IsInfinity($Value))) { return [string]$Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) { $result[[string]$key] = ConvertTo-AzureSqlJsonValue $Value[$key] }
        return [PSCustomObject]$result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-AzureSqlJsonValue $_ })
    }
    if ($Value -is [PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-AzureSqlJsonValue $property.Value
        }
        return [PSCustomObject]$result
    }
    return $Value
}

function ConvertTo-AzureSqlResultSet {
    param([object]$Value, [string]$DefaultName = 'Table')

    if ($Value -is [System.Data.DataTable]) {
        $columns = @($Value.Columns | ForEach-Object {
            [ordered]@{ Name = $_.ColumnName; Type = Get-AzureSqlTypeName $_.DataType }
        })
        $rows = @($Value.Rows | ForEach-Object {
            $row = [ordered]@{}
            foreach ($column in $Value.Columns) { $row[$column.ColumnName] = ConvertTo-AzureSqlJsonValue $_[$column] }
            [PSCustomObject]$row
        })
        return [PSCustomObject][ordered]@{
            Name = [string]($Value.TableName ? $Value.TableName : $DefaultName)
            Columns = $columns
            Rows = $rows
        }
    }

    $candidateRows = @($Value)
    if ($candidateRows.Count -gt 0 -and $candidateRows[0] -is [System.Data.DataRow]) {
        $table = $candidateRows[0].Table
        $columns = @($table.Columns | ForEach-Object {
            [ordered]@{ Name = $_.ColumnName; Type = Get-AzureSqlTypeName $_.DataType }
        })
        $rows = @($candidateRows | ForEach-Object {
            $dataRow = $_
            $row = [ordered]@{}
            foreach ($column in $table.Columns) { $row[$column.ColumnName] = ConvertTo-AzureSqlJsonValue $dataRow[$column] }
            [PSCustomObject]$row
        })
        return [PSCustomObject][ordered]@{
            Name = [string]($table.TableName ? $table.TableName : $DefaultName)
            Columns = $columns
            Rows = $rows
        }
    }

    if ((Test-AzureSqlObjectMember $Value 'Columns') -and (Test-AzureSqlObjectMember $Value 'Rows')) {
        $name = [string](Get-AzureSqlObjectValue $Value 'Name' $DefaultName)
        $columns = @(Get-AzureSqlObjectValue $Value 'Columns' @() | ForEach-Object {
            [ordered]@{ Name = [string](Get-AzureSqlObjectValue $_ 'Name'); Type = [string](Get-AzureSqlObjectValue $_ 'Type' 'nvarchar') }
        })
        $rows = @(Get-AzureSqlObjectValue $Value 'Rows' @() | ForEach-Object { ConvertTo-AzureSqlJsonValue $_ })
        return [PSCustomObject][ordered]@{ Name = $name; Columns = $columns; Rows = $rows }
    }

    $rows = $candidateRows
    $columnMap = [ordered]@{}
    foreach ($row in $rows) {
        if ($row -is [System.Collections.IDictionary]) {
            foreach ($key in $row.Keys) {
                if (-not $columnMap.Contains([string]$key)) {
                    $raw = $row[$key]
                    $columnMap[[string]$key] = Get-AzureSqlTypeName ($null -eq $raw ? [string] : $raw.GetType())
                }
            }
        }
        elseif ($null -ne $row) {
            foreach ($property in $row.PSObject.Properties) {
                if (-not $columnMap.Contains($property.Name)) {
                    $raw = $property.Value
                    $columnMap[$property.Name] = Get-AzureSqlTypeName ($null -eq $raw ? [string] : $raw.GetType())
                }
            }
        }
    }
    $columns = @($columnMap.Keys | ForEach-Object { [ordered]@{ Name = $_; Type = $columnMap[$_] } })
    return [PSCustomObject][ordered]@{
        Name = $DefaultName
        Columns = $columns
        Rows = @($rows | ForEach-Object { ConvertTo-AzureSqlJsonValue $_ })
    }
}

function ConvertTo-AzureSqlJsonResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Write', 'Query', 'Delete')][string]$Operation,
        [object]$Value,
        [AllowNull()][Nullable[int]]$DefaultRowsAffected = $null,
        [object]$OutputParameters = $null
    )

    $rowsAffected = $DefaultRowsAffected
    $resultSetsValue = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Value -and (Test-AzureSqlObjectMember $Value 'ResultSets')) {
        if (Test-AzureSqlObjectMember $Value 'RowsAffected') { $rowsAffected = Get-AzureSqlObjectValue $Value 'RowsAffected' }
        if (Test-AzureSqlObjectMember $Value 'OutputParameters') { $OutputParameters = Get-AzureSqlObjectValue $Value 'OutputParameters' }
        # Read directly so PowerShell does not pipeline-enumerate DataTable
        # values (an empty table would otherwise disappear here).
        $declaredSets = if ($Value -is [System.Collections.IDictionary]) {
            $Value['ResultSets']
        }
        else {
            $Value.ResultSets
        }
        if ($declaredSets -is [System.Data.DataTable]) {
            $resultSetsValue.Add($declaredSets)
        }
        else {
            foreach ($declaredSet in $declaredSets) { $resultSetsValue.Add($declaredSet) }
        }
    }
    elseif ($Value -is [System.Data.DataSet]) {
        foreach ($table in $Value.Tables) { $resultSetsValue.Add($table) }
    }
    elseif ($Value -is [System.Data.DataTable]) {
        $resultSetsValue.Add($Value)
    }
    elseif ($Value -is [System.Data.DataRow]) {
        $resultSetsValue.Add($Value)
    }
    elseif ($Value -is [object[]] -and @($Value).Count -gt 0 -and @($Value)[0] -is [System.Data.DataRow]) {
        $resultSetsValue.Add([object[]]$Value)
    }
    elseif ($Operation -eq 'Delete' -and $Value -is [ValueType]) {
        $rowsAffected = [int]$Value
        # A nonquery execution may return an affected-row count directly.
    }
    elseif ($null -ne $Value) {
        # A plain collection represents rows in one result set. Multiple result
        # sets are expressed with DataSet or the explicit ResultSets envelope.
        $resultSetsValue.Add($Value)
    }

    $sets = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($set in $resultSetsValue) {
        $name = $set -is [System.Data.DataTable] -and -not [string]::IsNullOrWhiteSpace($set.TableName) ? $set.TableName : ($index -eq 0 ? 'Table' : "Table$($index + 1)")
        $sets.Add((ConvertTo-AzureSqlResultSet -Value $set -DefaultName $name))
        $index++
    }

    if ($null -eq $OutputParameters) { $OutputParameters = [ordered]@{} }
    $envelope = [ordered]@{
        Operation = $Operation
        RowsAffected = $rowsAffected
        OutputParameters = ConvertTo-AzureSqlJsonValue $OutputParameters
        ResultSets = @($sets)
    }
    return ConvertTo-Json -InputObject $envelope -Depth 100 -Compress
}
