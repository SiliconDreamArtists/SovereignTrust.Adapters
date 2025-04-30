class LocalFileSystem {
    [object]$Jacket

    LocalFileSystem() {
        # Empty constructor for flexibility
    }

    [Signal] Construct([object]$dictionary) {
        $signal = [Signal]::new("Construct-LocalFileSystem")

        try {
            if ($null -eq $dictionary) {
                return $signal.LogCritical("Cannot construct LocalFileSystem — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $signal.LogInformation("LocalFileSystem constructed successfully with provided jacket.")
        }
        catch {
            $signal.LogCritical("Error constructing LocalFileSystem: $_")
        }

        return $signal
    }

    [Signal] ReadObjectAsJson([string]$folder, [string]$fileName) {
        return Get-JsonFromFile -Folder $folder -FileName $fileName
    }

    [Signal] ReadObjectAsXml([string]$folder, [string]$fileName) {
        return Get-XmlFromFile -Folder $folder -FileName $fileName
    }

    [Signal] DeleteFile([string]$folder, [string]$fileName) {
        return Remove-FileFromFileSystem -Folder $folder -FileName $fileName
    }

    [Signal] ListDirectoryObjects([string]$folder) {
        return Get-FileListFromDirectory -Folder $folder
    }
}
