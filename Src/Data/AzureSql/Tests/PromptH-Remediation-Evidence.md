# Prompt H remediation evidence

Captured 2026-09-24 on Windows x64 with PowerShell 7.6.6. This is a working-tree snapshot, not a commit or a deployment attestation. No live readiness variables were present. `az account show --output none` reported no Azure CLI login; no Key Vault resource or operational SQL secret was retrieved.

## Source and package state

Repository heads: `SovereignTrust.Adapters` `a808ffa2b38892256036e8830b9c3bac689e84d5`; `SovereignTrust.Foundation` `f55e41b1402ba14974275741fff312a8d8921c56`; `SDAFusion-Content` `d481d0e9aa605a8ad565a94a1900512c0b831a99`.

The adapter working tree contains modified production module files (`ConvertTo-AzureSqlJsonResult.ps1`, `Data_AzureSql.ps1/.psd1/.psm1`, `Invoke-Data_AzureSql.ps1`), `README.md`, two older test files, and both implementation-plan documents. Untracked adapter files are `.gitignore`, `Package-AzureSql.ps1`, `Packaging/`, the nine new operation/provider/normalization helper scripts, and the configuration, connection/parameter, execution-boundary, loader, normalization, import, routing, package, and Prompt G/H test support under `Tests/`. This remediation added `Launch-AzureSqlLiveIntegration.ps1`, extended `Run-AzureSqlLiveIntegration.ps1`, prepared `Provision-AzureSqlLiveFixture.template.sql`, and updated the README; the adapter implementation and packaged files were not changed during this remediation.

Foundation has modified `FabCondenser.ps1` and five mapped-adapter/plan-execution test scripts from the preceding Prompt H work. Content has the modified `SDA/Config/SDAFusionApp.Json` AzureSql jacket. The other modified or untracked Content files (`Artifact*.Json`, `Set.Json`, artifact activity tests, and `Working/Artifact-Sql-*`) are unrelated workspace edits and were not used as AzureSql validation evidence.

The current `PowerShell/` artifact has 64 files. Its identity is SHA-256 over sorted lines of `relative/path SHA256(file)`, joined with LF: `D6355E08110EC01D708DAD470E577CF4EFEFFE766F337EAE3C323E7E4DA72307`.

| Current file | SHA-256 |
|---|---|
| `Data_AzureSql.psd1` | `47910DB4D496FA744300D68BF65E1249F9EB02BFE44F3A28D2AB0B7BFEF63C13` |
| `Data_AzureSql.psm1` | `EF68618CAABD2DF1A39D475F780EF9C83FD7DF467CAC8BA745015A1251FBC35F` |
| `dependencies/inventory.json` | `73CBA6A288C3A2BC8B456CE620D6F3F65602218DF9A4877F51B4118E3F29A2B4` |
| `dependencies/Microsoft.Data.SqlClient.dll` | `A0CC09B728BF31B393150A02B237454665BD9FD8E99E8F2D4AE0E69BE015236F` |
| `dependencies/Microsoft.Data.SqlClient.SNI.dll` | `4B699D5208390414848B2165F8AE442504852AFD87221169233A5D7C7BDA4FF9` |
| `SDAFusionApp.Json` | `F0630BF97910FCB7B03BE4D70B63A81FD5A6DA4484A5AD1C09ECAC97F6FAB787` |

These hashes describe the current files. They do **not** prove the exact bytes used by a test run before they were captured. Session edit history shows that subsequent changes were limited to the live harness and documentation; the offline adapter and package evidence is reused on that basis. A fresh `Test-AzureSqlPackage.ps1` run on 2026-09-24 bound current package-loading behavior to this snapshot without rebuilding it.

## Commands and results

| Command from adapter repository root | Result | Scope |
|---|---|---|
| `pwsh -NoProfile -File Src/Data/AzureSql/Tests/Run-PromptHChecks.ps1` (preceding Prompt H run) | Pass for seven adapter suites, separate explicit-import and lazy-resolution processes, and five Foundation regressions; live exit 77 | Offline behavior and fresh-process routing on PowerShell 7.6.6 |
| `pwsh -NoProfile -File Src/Data/AzureSql/Tests/Test-AzureSqlPackage.ps1` with temporary SignalGraph module path (2026-09-24) | Pass: packaged provider/native load and isolated managed/native missing-file failures | Current win-x64 package on PowerShell 7.6.6 |
| `pwsh -NoProfile -File Src/Data/AzureSql/Tests/Launch-AzureSqlLiveIntegration.ps1 -TargetProbe` (2026-09-24) | Exit 77: approved server and database unknown | No protected resource accessed |
| `pwsh -NoProfile -File Src/Data/AzureSql/Tests/Launch-AzureSqlLiveIntegration.ps1 -FixtureProbe` (2026-09-24) | Exit 77: approved target and dedicated schema unknown | No protected resource accessed |
| `pwsh -NoProfile -File Src/Data/AzureSql/Tests/Launch-AzureSqlLiveIntegration.ps1` (2026-09-24) | Exit 77: live prerequisites absent | No mutation attempted |

The launcher creates a temporary SignalGraph junction, starts a fresh `pwsh -NoProfile` child, restores `PSModulePath`, and propagates 0, 77, or failure. The read-only target probe checks production hydration, lazy module resolution, SqlClient authentication, connection-string server/catalog, and `DB_NAME()` before any mutation. The fixture probe checks schema, shape, procedure definition/dependencies, triggers, and visible effective permissions without readiness flags. These probes have not run past their gates.

No dedicated fixture DDL was found in the current checked-out repositories outside the adapter's test contract and copied design snapshots. Actual database objects remain unknown. The new SQL provisioning template has not been executed; it requires a provisioning owner and an approved dedicated target.

## Completion criteria

| Plan criterion | Evidence | Status |
|---|---|---|
| Production virtual-path resolution without manual implementation import/registration | `Smoke-AzureSqlLazyResolution.ps1` through Fab and `Data.FusionDatabase` | Verified offline; deployment unverified |
| Real Write, Query, Delete through mapped route | `Run-AzureSqlLiveIntegration.ps1` | Unverified live |
| SQL text separate from typed values | `Data_AzureSql.ConnectionParameters.Tests.ps1`, execution-boundary suite | Verified offline |
| Stored-procedure Write with normalized JSON | normalization and execution-boundary suites | Verified offline; live unverified |
| Empty/multiple result sets with metadata | adapter and execution-boundary suites | Verified offline; live unverified |
| Delete zero versus unknown affected count | execution-boundary suite | Verified offline; live unverified |
| Valid JSON and no provider objects at result boundary | adapter and execution-boundary suites | Verified offline; live unverified |
| Failed mutation rollback | execution-boundary suite | Verified offline; live unverified |
| No committed/logged secrets or tokens | protected config expression and synthetic sanitization tests; no operational secret printed | Live/deployment unverified |
| Caller plan and input unchanged | normalization and adapter suites | Verified offline |
| Focused integration and existing regressions pass | offline suites and Foundation regressions pass; live exit 77 | Unverified overall |

PowerShell 7.4 is advertised in the manifest, but only 7.6.6 was available on this host. The intended deployment host and its runtime have not been identified or tested. Overall completion remains blocked by approved-target, authentication/network, fixture/permission, live-scenario, cleanup, and deployment-runtime validation.

## Exact working-tree status at capture

The following is `git status --short` from each repository, including this untracked evidence file.

### SovereignTrust.Adapters

```text
 M Src/Data/AzureSql/PowerShell/ConvertTo-AzureSqlJsonResult.ps1
 M Src/Data/AzureSql/PowerShell/Data_AzureSql.ps1
 M Src/Data/AzureSql/PowerShell/Data_AzureSql.psd1
 M Src/Data/AzureSql/PowerShell/Data_AzureSql.psm1
 M Src/Data/AzureSql/PowerShell/Invoke-Data_AzureSql.ps1
 M Src/Data/AzureSql/README.md
 M Src/Data/AzureSql/Tests/Data_AzureSql.Routing.Tests.ps1
 M Src/Data/AzureSql/Tests/Data_AzureSql.Tests.ps1
 M docs/AzureSql-Data-Adapter-Implementation-Plan-Prompts.md
 M docs/AzureSql-Data-Adapter-Implementation-Plan.md
?? Src/Data/AzureSql/.gitignore
?? Src/Data/AzureSql/Package-AzureSql.ps1
?? Src/Data/AzureSql/Packaging/
?? Src/Data/AzureSql/PowerShell/Add-AzureSqlParameters.ps1
?? Src/Data/AzureSql/PowerShell/Import-AzureSqlProvider.ps1
?? Src/Data/AzureSql/PowerShell/Invoke-AzureSqlDelete.ps1
?? Src/Data/AzureSql/PowerShell/Invoke-AzureSqlQuery.ps1
?? Src/Data/AzureSql/PowerShell/Invoke-AzureSqlWrite.ps1
?? Src/Data/AzureSql/PowerShell/New-AzureSqlCommand.ps1
?? Src/Data/AzureSql/PowerShell/New-AzureSqlSession.ps1
?? Src/Data/AzureSql/PowerShell/Open-AzureSqlConnection.ps1
?? Src/Data/AzureSql/PowerShell/Resolve-AzureSqlWriteInput.ps1
?? Src/Data/AzureSql/Tests/Data_AzureSql.Configuration.Tests.ps1
?? Src/Data/AzureSql/Tests/Data_AzureSql.ConnectionParameters.Tests.ps1
?? Src/Data/AzureSql/Tests/Data_AzureSql.ExecutionBoundary.Tests.ps1
?? Src/Data/AzureSql/Tests/Data_AzureSql.LoaderHydration.Tests.ps1
?? Src/Data/AzureSql/Tests/Data_AzureSql.Normalization.Tests.ps1
?? Src/Data/AzureSql/Tests/Launch-AzureSqlLiveIntegration.ps1
?? Src/Data/AzureSql/Tests/Provision-AzureSqlLiveFixture.template.sql
?? Src/Data/AzureSql/Tests/PromptH-Remediation-Evidence.md
?? Src/Data/AzureSql/Tests/Run-AzureSqlLiveIntegration.ps1
?? Src/Data/AzureSql/Tests/Run-PromptGChecks.ps1
?? Src/Data/AzureSql/Tests/Run-PromptHChecks.ps1
?? Src/Data/AzureSql/Tests/Smoke-AzureSqlImport.ps1
?? Src/Data/AzureSql/Tests/Smoke-AzureSqlLazyResolution.ps1
?? Src/Data/AzureSql/Tests/SqlClientDecimalFixture.ps1
?? Src/Data/AzureSql/Tests/Test-AzureSqlPackage.ps1
```

### SovereignTrust.Foundation

```text
 M Src/PowerShell/Classes/Adapters/Condenser/FabCondenser.ps1
 M Tests/Complete-PlanPhaseTask.Tests.ps1
 M Tests/Invoke-PlanIteration.Tests.ps1
 M Tests/LazyAdapterLoading.Tests.ps1
 M Tests/PlanCondenser.InvokePhaseAsync.Tests.ps1
 M Tests/PlanCondenser.IteratePhase.Tests.ps1
```

### SDAFusion-Content

```text
 M SDA/Config/SDAFusionApp.Json
 M SDA/SDA/Artifact.Json
 M SDA/SDA/Artifact_Enrollment.Json
 M SDA/SDA/Set.Json
?? SDA/SDA/Artifact_External.Json
?? SDA/SDA/Artifact_Images.Json
?? SDA/Tests/Test-ArtifactActivityPlans.ps1
?? SDA/Tests/Test-PublishImageEligibility.ps1
?? Working/Artifact-Sql-Design/
?? Working/Artifact-Sql-Ingestion-Plan.md
```
