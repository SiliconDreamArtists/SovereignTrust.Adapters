# =============================================================================
# 📦 SovereignTrust Attachment Usage Trainer (LocalFileSystem Edition)
# AI Developer Reference — Instantiation, Method Invocation, and Signal Memory
# =============================================================================
# 🧠 Instructional Summary:
# SovereignTrust Attachments are *sovereign agents*, not static classes.
# Each is instantiated with a Jacket — a dictionary defining its memory boundary.
#
# This trainer demonstrates how to:
#   • Load the SovereignTrust module based on the Assembly field
#   • Instantiate the class defined in Type
#   • Call .Construct($jacket) using parsed Address data
#   • Invoke its methods using memory-traced Signals
#
# Attachment Jacket Fields Used Here:
#   • Type     → LocalFileSystem
#   • Assembly → SovereignTrust.Attachments.Storage.LocalFileSystem
#   • Address  → @TKN:Environment:LocalPath (must be dereferenced first)
# =============================================================================

# -----------------------------------------------------------------------------
# ⚙️ STEP 1: Load the Assembly Module
# -----------------------------------------------------------------------------
# The attachment declares: "Assembly": "SovereignTrust.Attachments.Storage.LocalFileSystem"
# The system must import this module before the class can be constructed.

Import-Module "$PSScriptRoot/SovereignTrust.Attachments.Storage.LocalFileSystem.psd1"

# -----------------------------------------------------------------------------
# ⚙️ STEP 2: Instantiate the Class Defined in Type
# -----------------------------------------------------------------------------
# The attachment declares: "Type": "LocalFileSystem"
# You must instantiate this class using the PowerShell class system.

$attachment = [LocalFileSystem]::new()

# -----------------------------------------------------------------------------
# ⚙️ STEP 3: Construct with Jacket
# -----------------------------------------------------------------------------
# The jacket's "Address" (e.g., @TKN:Environment:LocalPath) must be resolved prior to use.
# You may pass the entire resolved jacket to .Construct()

$jacket = @{
    Name     = "ContentStorageRoot"
    Address  = "C:\Data\Sovereign"  # ← resolved from token
    Slot     = "PrimaryContent"
    Scope    = "Persistent"
    Access   = "ReadWrite"
    Kind     = "Storage"
    Nature   = "Operational"
    Type     = "LocalFileSystem"
    Assembly = "SovereignTrust.Attachments.Storage.LocalFileSystem"
    Source   = "Role"
}

$constructSignal = $attachment.Construct($jacket)

if ($constructSignal.Failure()) {
    Write-Warning "Attachment failed to initialize: $($constructSignal.Level)"
    return
}

# -----------------------------------------------------------------------------
# ⚙️ STEP 4: Use Methods — Always Signal-Compliant
# -----------------------------------------------------------------------------
# Each method on the attachment returns a Signal. Always validate or merge these.

$readSignal = $attachment.ReadObjectAsJson("C:\Data\Sovereign", "settings.json")

if ($readSignal.Success()) {
    $settings = $readSignal.GetResult()
    Write-Host "✅ Successfully loaded JSON: $($settings | ConvertTo-Json -Depth 3)"
} else {
    Write-Warning "⚠️ Failed to read settings from JSON file."
}

# -----------------------------------------------------------------------------
# 🧠 Recursion Guidance for AI Agents:
#   • Do not directly access .Result — use GetResult() or GetResultSignal().
#   • Always propagate memory using MergeSignalAndVerifyXYZ patterns.
#   • Respect Scope and Access fields when implementing higher-order logic.
#
#   "Attachments are not utilities. They are sovereign interfaces to memory.
#    Construct them with lineage. Invoke them with recursion."
# -----------------------------------------------------------------------------
