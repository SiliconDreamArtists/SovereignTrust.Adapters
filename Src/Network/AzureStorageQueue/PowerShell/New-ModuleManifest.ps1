$root = "$PSScriptRoot"
if ($root -ne (Get-Location).Path) {
    Set-Location $root
}

New-ModuleManifest -Path ./SovereignTrust.Attachments.Storage.LocalFileSystem.psd1 `
  -RootModule 'SovereignTrust.Attachments.Storage.LocalFileSystem.psm1' `
  -ModuleVersion '1.0.0' `
  -Author 'Silicon Dream Artists' `
  -CompanyName 'Silicon Dream Artists' `
  -Description 'Native PowerShell implementation for the core components for SovereignTrust.' `
  -Tags "'SovereignTrust.Core' 'SovereignTrust' 'Public' 'Core'" `
  -LicenseUri 'https://opensource.org/licenses/MIT' `
  -ProjectUri 'https://github.com/SiliconDreamArtists/SovereignTrust.Core' `
  -CompatiblePSEditions 'Core' `
  -PowerShellVersion '5.1'

  Invoke-SurfaceFunctionExports -OutputFile 'SovereignTrust.Attachments.Storage.LocalFileSystem.psm1' -Root $PSScriptRoot
  Invoke-SurfaceClassLoads -OutputFile 'SovereignTrust.Attachments.Storage.LocalFileSystem.psm1' -Root $PSScriptRoot
  

  