# =============================================================================
# LocalFileSystem Storage Module (Signal Compliant)
# SovereignTrust Attachments • SDA Standard Storage Attachment
# =============================================================================

# --- Internal Tools ---
function Get-VirtualFilePath {
    param (
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [string]$FileName
    )

    $folder = $Folder -replace '\\', '/'
    if (![string]::IsNullOrWhiteSpace($folder)) {
        $folder = $folder.Trim('/') + '/'
    }

    return "$folder$FileName"
}

# --- Read Operations ---
function Get-JsonFromFile {
    param (
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [string]$FileName
    )

    $path = Get-VirtualFilePath -Folder $Folder -FileName $FileName
    $signal = [Signal]::new("Get-JsonFromFile:$path")

    try {
        if (!(Test-Path -Path $path)) {
            $signal.LogCritical("File not found: $path")
            return $signal
        }

        $jsonString = Get-Content -Path $path -Raw
        $parsedObject = $jsonString | ConvertFrom-Json

        $signal.SetResult($parsedObject)
        $signal.LogInformation("Successfully loaded JSON object from $path.")
    }
    catch {
        $signal.LogCritical("Error loading JSON from $($path): $_")
    }

    return $signal
}

function Get-XmlFromFile {
    param (
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [string]$FileName
    )

    $path = Get-VirtualFilePath -Folder $Folder -FileName $FileName
    $signal = [Signal]::new("Get-XmlFromFile:$path")

    try {
        if (!(Test-Path -Path $path)) {
            $signal.LogCritical("File not found: $path")
            return $signal
        }

        $xmlDocument = [xml](Get-Content -Path $path -Raw)

        $signal.SetResult($xmlDocument)
        $signal.LogInformation("Successfully loaded XML object from $path.")
    }
    catch {
        $signal.LogCritical("Error loading XML from $($path): $_")
    }

    return $signal
}

function Remove-FileFromFileSystem {
    param (
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [string]$FileName
    )

    $path = Get-VirtualFilePath -Folder $Folder -FileName $FileName
    $signal = [Signal]::new("Remove-FileFromFileSystem:$path")

    try {
        if (Test-Path -Path $path) {
            Remove-Item -Path $path -Force
            $signal.LogInformation("File deleted: $path.")
        }
        else {
            $signal.LogWarning("File to delete not found: $path.")
        }
    }
    catch {
        $signal.LogCritical("Error deleting file: $_")
    }

    return $signal
}

function Get-FileListFromDirectory {
    param (
        [Parameter(Mandatory)] [string]$Folder
    )

    $signal = [Signal]::new("Get-FileListFromDirectory:$Folder")

    try {
        if (!(Test-Path -Path $Folder)) {
            $signal.LogCritical("Folder not found: $Folder")
            return $signal
        }

        $files = Get-ChildItem -Path $Folder | Select-Object -ExpandProperty Name
        $signal.SetResult($files)
        $signal.LogInformation("Listed files in folder: $Folder.")
    }
    catch {
        $signal.LogCritical("Error listing directory contents: $_")
    }

    return $signal
}

############################SovereignTrust.Attachments.Storage.LocalFileSystem.psm1############
Export-ModuleMember -Function 'Get-VirtualFilePath'
Export-ModuleMember -Function 'Get-JsonFromFile'
Export-ModuleMember -Function 'Get-XmlFromFile'
Export-ModuleMember -Function 'Remove-FileFromFileSystem'
Export-ModuleMember -Function 'Get-FileListFromDirectory'

############################CLASS_LOADS############
. "$PSScriptRoot/LocalFileSystem.ps1"


