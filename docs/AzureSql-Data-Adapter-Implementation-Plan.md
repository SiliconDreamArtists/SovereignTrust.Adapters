# Azure SQL Data Adapter Implementation Plan

## Objective

Implement a production `Data.AzureSql` adapter that follows the module, construction, invocation, configuration, and signal conventions used by `SovereignTrust.Adapters/Src/Storage/AzureStorageAccount`.

The completed route is:

```text
Plan / MemoryCondenser
  -> Data.FusionDatabase                   [Data.<Slot>]
  -> MappedDataAdapter                     [SovereignTrust.Foundation]
  -> FusionDatabase slot
  -> SovereignTrust.Adapters.Data.AzureSql [adapter implementation]
  -> JSON result in Signal
```

The adapter will execute real Azure SQL commands. The mock implementation, in-memory state, mock handlers, fixture matching, reset behavior, invocation recording, and injected failures are not part of the target design.

## 1. Use the mapped Data slot directly

Plans invoke the adapter with `Adapter: Data.FusionDatabase`, following the standard `Kind.Slot` convention. The generic mapped-adapter infrastructure resolves `Data` to `MappedDataAdapter` and `FusionDatabase` to the registered slot implementation.

The virtual path separates the implementation from the slot:

```text
SovereignTrust.Adapters.Data.AzureSql.FusionDatabase.Persistent.Full
|-------------------------------------| |------------| |--------| |--|
             adapter path                  slot         nature   access
```

- `SovereignTrust.Adapters.Data.AzureSql` identifies the adapter module and type.
- `FusionDatabase` is the mapped slot name used by plans.
- `Persistent` is the configured nature.
- `Full` is the configured access.

There is no `Condenser.Data`, `DataCondenser`, or `Config.DataAdapter` hop in this design.

Foundation remains responsible only for generic mapped-adapter routing and signal propagation. Foundation must not contain:

- Azure SQL connection or command implementation.
- `Microsoft.Data.SqlClient` dependencies.
- SQL parameter construction.
- Database-result conversion.
- Azure SQL authentication logic.
- Azure SQL input normalization.

`Data_AzureSql` is responsible for:

- Validating `Write`, `Query`, and `Delete` plans.
- Resolving exactly one of `Content` or `ContentPath` for Write.
- Normalizing JSON, PowerShell objects, and CSV input for stored-procedure ingestion.
- Preserving `Int32`, `Int64`, `Decimal`, `Guid`, `DateTime`, `byte[]`, nulls, dictionaries, and arrays in SQL parameters.
- Preserving empty and one-element top-level arrays in document mode.
- Leave the original plan and input unchanged on success and failure.

The adapter should treat the incoming plan as immutable and prepare local command values rather than rewriting or cloning the plan. If the provisional `DataCondenser` was introduced solely for AzureSql, remove its registration, helpers, and dedicated tests after confirming that no independent consumer uses it.

Before removing those helpers and tests, record their reusable normalization contracts and test cases in a migration checklist in this plan. Preserve the input/output examples and assertions needed for AzureSql-owned coverage; do not preserve obsolete condenser routing or plan-cloning behavior.

The Write normalization contract carries forward these input conventions:

- Resolve `Config.ContentPath` against `ItemSignal` using `Resolve-PathFromDictionary`, for example `@.Payload`. It is a signal/dictionary path, not a filesystem path. Propagate resolution failures through a failed signal.
- Determine whether `Content` or `ContentPath` is supplied by member presence; reject both or neither, then validate the selected value.
- Support `InputFormat` values `Object`, `Json`, and `Csv`, defaulting to `Object` when omitted.
- Support `PayloadMode` values `Records` and `Document`, defaulting to `Records` when omitted. Reject unsupported values; CSV supports only `Records`.
- Retain CSV `Delimiter` support with a comma default and exactly one character when specified.
- Retain the existing optional `ColumnSchema` contract for Records, including its dictionary and Name/Type descriptor forms and supported conversions. Apply conversions to newly prepared payload rows without mutating caller values. Document and test the supported types and invalid-conversion failures.

## 2. Refactor AzureSql into a production adapter

### Prompt B migration checklist (captured before provisional cleanup)

Source contracts: `SovereignTrust.Foundation/Src/PowerShell/Utilities/Adapters/Condenser/Data/Test-DataCondenserPlan.ps1`, `Resolve-DataCondenserPayload.ps1`, and `SovereignTrust.Foundation/Tests/DataCondenser.Tests.ps1`. These files were provisional AzureSql-only code. Reimplement the following in AzureSql-owned normalization and tests; do not restore `Condenser.Data`, `Config.DataAdapter`, cloned plans, or pre-normalized `Config.Content` mutation.

- [ ] Accept exactly one **member** of `Config.Content` and `Config.ContentPath`; both or neither fail, even when a member has a null value. Reject empty `ContentPath`. Resolve a path such as `@.Payload` against `ItemSignal` with `Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $contentPath`. Merge resolution failures into the operation signal and fail when no result is returned. Treat the path as a signal/dictionary path.
- [ ] Require `Plan.Config`; Write requires nonblank `Procedure`; Query and Delete require nonblank `CommandText`. Reject unsupported activities. These validations belong to `Data_AzureSql` and must not require `Config.DataAdapter`.
- [ ] `InputFormat` accepts `Object`, `Json`, `Csv`, default `Object`. `Object` uses the selected content directly. `Json` parses string content with `ConvertFrom-Json -Depth 100` and uses nonstring content directly; malformed JSON fails. `Csv` requires text, parses with `ConvertFrom-Csv`, and supports only `PayloadMode=Records`.
- [ ] `PayloadMode` accepts `Records` and `Document`, default `Records`; reject other values. Records reject null payload, require each row to be a dictionary or `PSCustomObject`, and serialize a top-level JSON array, including zero or one record. Document serializes the selected value as one JSON document and must preserve nested objects and empty or one-element top-level arrays.
- [ ] CSV `Delimiter` defaults to comma and, when supplied, must contain exactly one character. Preserve quoted fields, empty values, and embedded newlines. For example `Id,Name` plus `2,"Gallery\r\nArchive"` yields one row with `Id="2"` before schema conversion and `Name="Gallery\r\nArchive"`. A semicolon delimiter should parse `Id;Name` when configured.
- [ ] Optional Records `ColumnSchema` accepts a dictionary such as `@{ Id = 'int' }` or descriptors such as `@(@{ Name = 'Id'; Type = 'int' })`. Apply matching column conversions to fresh output rows, leaving caller rows untouched; retain unlisted columns and null values. Supported aliases: `string/nvarchar/varchar/text` to string; `int/int32` to Int32; `long/int64/bigint` to Int64; `decimal/numeric` to Decimal; `double/float` to Double; `bool/boolean/bit` to Boolean; `date/datetime/datetime2/datetimeoffset` to DateTimeOffset. Parse numeric and date values with invariant culture. Unknown types, invalid values, and nonobject Records entries fail.
- [ ] Preserve these test fixtures/assertions from `DataCondenser.Tests.ps1`: Object Records `@([pscustomobject]@{Id='1';Name='Museum'})` with `ColumnSchema=@{Id='int'}` yields `[{'Id':1,'Name':'Museum'}]`, with converted `Id` numeric; CSV with a quoted embedded newline preserves that newline and converts `Id` to 2; `ItemSignal` result `{Payload:{Metadata:{Name:'WeatherVault';Version:1}}}` with `ContentPath='@.Payload'`, Object/Document yields nested `Metadata.Name='WeatherVault'`; both Content and ContentPath fail; malformed JSON fails. Add empty and single-element Document array assertions and invalid delimiter/schema conversion assertions. Compare caller plan and input before/after both success and failure; local normalized JSON must never be written into them.
- [ ] Preserve unrelated query/delete contract assertions at the adapter boundary: parameters and `CommandTimeoutSeconds` reach execution unchanged, successful JSON result is forwarded unchanged, and downstream failure becomes a failed signal. Replace the prior condenser-routing assertion with direct `Data.FusionDatabase` mapped routing.

Keep the adapter under:

```text
SovereignTrust.Adapters/Src/Data/AzureSql/
  PowerShell/
    Data_AzureSql.ps1
    Data_AzureSql.psm1
    Data_AzureSql.psd1
    Open-AzureSqlConnection.ps1
    New-AzureSqlCommand.ps1
    Add-AzureSqlParameters.ps1
    Invoke-AzureSqlWrite.ps1
    Invoke-AzureSqlQuery.ps1
    Invoke-AzureSqlDelete.ps1
    ConvertTo-AzureSqlJsonResult.ps1
  Tests/
```

Model its lifecycle after `Storage_AzureStorageAccount`:

- Provide a `Data_AzureSql` class.
- Provide a parameterless constructor.
- Implement `Construct([object]$dictionary)` and retain the hydrated adapter jacket.
- Implement `[Signal] Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal)`.
- Export `Resolve-Data_AzureSql` from the module.
- Load operation helpers from the module entry point.
- Read adapter-level configuration from the constructed jacket.
- Read operation-level configuration from `Plan.Config`.
- Return unsupported activities and all execution errors as failed signals.

Establish the injectable internal execution boundary during this structural refactor, before implementing connections and operations. Define how tests substitute connection, command, reader, and transaction interactions while exercising the adapter's real validation, conversion, and orchestration logic. Keep the boundary internal; do not expose mock handlers or a mock mode through production configuration. Later implementation steps must reuse this boundary.

The step 2 scaffold uses private `Invoke-AzureSqlExecution` inside the module as the only call from `Data_AzureSql.Invoke` into execution. It receives the constructed adapter (and thus its hydrated jacket), slot, activity, original plan/config, and both signals. It currently fails with an explicit pending-implementation error. The direct mapped-routing test substitutes this private function in module scope to verify routing and signal propagation without SQL state. When implementing steps 5–12, keep this entry point as the real validation/orchestration path and place provider creation behind an internal session factory. Tests should replace that factory with a connection double whose `Open`, `CreateCommand`, and `BeginTransaction` return command, reader, and transaction doubles; cover `ExecuteReader`/`ExecuteNonQuery`, `Read`/`NextResult`/schema/value access, `Commit`/`Rollback`, and disposal while the real adapter code runs. Do not expose the factory or doubles in adapter configuration. The current routing substitute is transitional and does not count as SQL operation coverage.

Remove all mock-only members and behavior:

- `Mode = Mock` requirements.
- `Data` and `SeedData` state.
- Procedure and command handlers.
- Reset support.
- Invocation recording.
- Injected failures.
- Mock configuration fixtures and mock-specific tests.

## 3. Package Microsoft.Data.SqlClient

Use `Microsoft.Data.SqlClient` rather than `System.Data.SqlClient`.

Add a pinned and repeatable dependency restore/package step that includes the provider and its runtime dependencies in the adapter module artifact. Runtime module import must not download packages.

The dependency work must:

- Pin the selected package version.
- Restore dependencies during build or packaging.
- Copy the appropriate managed and native runtime assets into the adapter artifact.
- Load the packaged provider before loading the adapter class.
- Fail module import with a clear message if required assemblies are unavailable.
- Work in a fresh PowerShell 7 process on the deployment target.

Update `Data_AzureSql.psd1` with an accurate description, explicit exports, PowerShell compatibility, and dependency metadata appropriate to the final package layout.

## 4. Configure the live adapter for sdadev01

Add the adapter mapping to:

```text
SDAFusion-Content/SDA/Config/SDAFusionApp.Json
Agents[Name=sdadev01].Roles.SDAWorkItems.Adapters
```

Configured adapter jacket:

```json
{
    "Name": "SDAFusionDatabase",
    "VirtualPath": "SovereignTrust.Adapters.Data.AzureSql.FusionDatabase.Persistent.Full",
    "IsMapped": true,
    "Resource": "[Storage.Secrets.Read.sdafusion-sqldatabase|]",
    "Addresses": [
        "https://sda-dev.vault.azure.net/"
    ]
}
```

Configuration responsibilities follow the AzureStorageAccount convention:

- `VirtualPath` selects the `AzureSql` adapter implementation and registers it in the `FusionDatabase` slot.
- `Resource` is hydrated through `Storage.Secrets.Read` and supplies the protected Azure SQL connection resource at runtime.
- `Addresses` remains the configured Key Vault address for this jacket; it is not an Azure SQL server endpoint and must not be used as the SQL data source.
- `Plan.Config` supplies the command or procedure and its parameters.

Do not store a resolved connection string, password, client secret, or access token in this file. The adapter must receive only the hydrated runtime value of `Resource`.

## 5. Implement secure connection construction

Read the hydrated connection resource from the adapter jacket's `Resource` value and parse it with `Microsoft.Data.SqlClient.SqlConnectionStringBuilder`. Do not construct a connection string through textual concatenation and do not treat the jacket's Key Vault `Addresses` value as a SQL endpoint.

The protected resource may select any explicitly supported SqlClient authentication mode. The preferred passwordless modes are:

- `Active Directory Default` for local development and general passwordless resolution.
- `Active Directory Managed Identity` for hosted execution, including an optional user-assigned identity.

Service-principal or SQL-password authentication may be supported when required, but their credentials must exist only in the protected secret value and must never be copied into plans, logs, or the application configuration.

Apply secure defaults:

```text
Encrypt=True
TrustServerCertificate=False
Application Name=SovereignTrust.Adapters.Data.AzureSql
```

Connection handling must:

- Validate that the hydrated `Resource` is present and is a valid supported connection resource.
- Require a SQL data source and initial catalog after parsing the resource.
- Enforce encryption and reject insecure certificate-trust settings unless an explicit, separately approved development override exists.
- Apply the connection timeout from the protected resource or a safe adapter default.
- Open a new connection for an invocation and dispose it deterministically.
- Avoid logging connection strings, credentials, tokens, or parameter values.
- Return authentication, firewall, DNS, timeout, and provider errors through a failed signal.

## 6. Define typed SQL parameters

Use parameter descriptors as the canonical plan representation:

```json
"Parameters": [
    {
        "Name": "@Id",
        "SqlDbType": "Int",
        "Value": 1
    },
    {
        "Name": "@Amount",
        "SqlDbType": "Decimal",
        "Precision": 18,
        "Scale": 4,
        "Value": 125.5000
    },
    {
        "Name": "@Result",
        "SqlDbType": "Int",
        "Direction": "Output"
    }
]
```

The adapter must:

- Construct `SqlParameter` objects explicitly.
- Convert null parameter values to `DBNull.Value`.
- Apply type, size, precision, scale, and direction.
- Support input, output, input/output, and return-value parameters.
- Reject unknown SQL types, invalid directions, and failed conversions.
- Keep parameter values separate from procedure names and SQL text.
- Never perform textual parameter substitution.

The existing dictionary parameter form may be retained as a compatibility format with conservative inference. Explicit descriptors take precedence and are required when size, precision, scale, direction, or an unambiguous database type matters.

Table-valued parameters are outside the initial scope because Write uses a normalized JSON payload. Unsupported structured parameters must fail explicitly.

## 7. Implement Write, Query, and Delete

### Write

- Require `Config.Procedure`.
- Use `CommandType.StoredProcedure`.
- Require locally normalized JSON text derived from exactly one of `Config.Content` or `Config.ContentPath`, following the input contract in section 1. Do not write the normalized text back into the caller's plan.
- Bind it to `Config.PayloadParameter`, defaulting to `@Payload`.
- Use `NVarChar(MAX)` for the payload parameter.
- Bind additional typed parameters.
- Execute the procedure and capture result sets, affected rows, output parameters, and the return value.

### Query

- Require `Config.CommandText`.
- Use `CommandType.Text`.
- Bind typed parameters independently from the SQL text.
- Execute a data reader.
- Traverse every result with `NextResult()`.
- Preserve empty result sets and their column metadata.

### Delete

- Require `Config.CommandText`.
- Use `CommandType.Text` and typed parameters.
- Execute with `ExecuteNonQuery()` when no result sets are expected.
- Preserve zero as `RowsAffected: 0`.
- Convert a provider result of `-1` to `RowsAffected: null`, because the affected count is unknown.

Apply `Config.CommandTimeoutSeconds` when present, otherwise use the adapter-level default. Do not automatically retry Write or Delete because their idempotency is unknown.

## 8. Enforce the JSON result boundary

Every successful operation must call `Signal.SetResult()` with valid JSON text using this common envelope:

```json
{
    "Operation": "Query",
    "RowsAffected": null,
    "OutputParameters": {},
    "ResultSets": [
        {
            "Name": "Table",
            "Columns": [
                {
                    "Name": "Id",
                    "Type": "int",
                    "Ordinal": 0,
                    "AllowDBNull": false,
                    "Precision": null,
                    "Scale": null
                }
            ],
            "Rows": []
        }
    ]
}
```

Use data-reader schema information so columns remain available when a result set contains no rows.

Conversion rules:

- Database null becomes JSON `null`.
- Binary values become base64 strings.
- GUID values become canonical strings.
- Date and time values use invariant ISO-8601 representations.
- Decimal values become invariant precision-preserving strings.
- Integers outside the JavaScript safe-integer range become strings.
- Safe integers and floating-point values remain JSON numbers.

No `SqlConnection`, `SqlCommand`, `SqlParameter`, `SqlDataReader`, `DataSet`, `DataTable`, or `DataRow` may escape through a result, output parameter, or signal jacket.

## 9. Make mutations transactional

Default Write and Delete operations to an explicit database transaction:

1. Open the connection.
2. Begin a transaction.
3. Create and execute the command.
4. Materialize all result sets and output parameters.
5. Serialize the complete JSON envelope.
6. Commit only after serialization succeeds.
7. Roll back when execution, conversion, or serialization fails.

Allow a narrowly documented configuration override only when a stored procedure cannot participate in an adapter-managed transaction. Query operations do not require an explicit transaction by default.

## 10. Update plans and examples

Write plans route directly through the mapped data slot:

```json
{
    "Name": "IngestRecords",
    "Adapter": "Data.FusionDatabase",
    "Activity": "Write",
    "Key": "IngestResult",
    "Config": {
        "InputFormat": "Json",
        "PayloadMode": "Records",
        "Content": [
            {
                "Id": 1,
                "Name": "Museum"
            }
        ],
        "Procedure": "dbo.IngestRecords",
        "PayloadParameter": "@Payload",
        "Parameters": []
    }
}
```

Query and Delete plans use `Config.CommandText`, typed `Config.Parameters`, and an optional `Config.CommandTimeoutSeconds`.

Examples must contain no operational credentials and must clearly distinguish placeholders from usable environment configuration.

## 11. Test the production adapter

### Unit and contract tests

Test without requiring an Azure connection where possible:

- AzureSql input normalization, immutable-plan behavior, and preservation of parameter value types.
- Connection-builder validation and secure defaults.
- Typed parameter construction and conversion.
- Null, decimal, binary, date, GUID, and output parameters.
- Command type and timeout selection.
- Empty and multiple result-set conversion.
- JSON envelope consistency.
- Resource disposal.
- Transaction commit and rollback control flow.
- Failed signals for invalid configuration and provider exceptions.

Use an injectable internal execution boundary for unit tests. Do not ship an in-memory SQL implementation as production adapter behavior.

### Clean-session module loading tests

Use two separate fresh PowerShell 7 processes:

1. An explicit-import smoke test imports Foundation and the packaged AzureSql module and verifies provider loading, factory resolution, and construction.
2. A production lazy-resolution test imports Foundation and required bootstrap dependencies only, with AzureSql initially unloaded. Load configuration and register jackets through the production loader, then invoke `Data.FusionDatabase` and verify that production resolution loads `Data_AzureSql.psd1`, calls `Resolve-Data_AzureSql`, and calls `Construct()` with the hydrated jacket. Do not pre-import AzureSql, dot-source its class, pre-call its factory, or manually register its implementation. Use the internal execution boundary for offline SQL execution checks without bypassing production module resolution.

Passing the explicit-import test does not establish that lazy resolution works.

### Live Azure SQL integration tests

Run gated tests against a dedicated integration database and schema:

1. Start a fresh PowerShell 7 process and import Foundation and required bootstrap dependencies only. Confirm AzureSql is initially unloaded; do not manually import or register its implementation.
2. Load the real `SDAFusionApp.Json` configuration.
3. Select agent `sdadev01` and role `SDAWorkItems`.
4. Register the adapter jackets through the production loader.
5. On the first mapped invocation, confirm production lazy resolution loads `Data_AzureSql.psd1`, calls `Resolve-Data_AzureSql`, and calls `Construct()` with the hydrated jacket.
6. Route through `Data.FusionDatabase -> MappedDataAdapter -> FusionDatabase -> Data_AzureSql`.
7. Write JSON records.
8. Write CSV records, including quoted values, empty values, and embedded newlines.
9. Ingest a nested JSON document.
10. Query multiple rows, no rows, and multiple result sets.
11. Delete selected records and verify the affected count.
12. Query the remaining records.
13. Exercise a failing command and verify rollback.
14. Confirm every successful result is valid JSON text and no database object escapes.

The live suite requires:

- The Azure SQL server endpoint.
- The database name.
- Network and firewall access from the test host.
- An authenticated identity.
- A contained database user with least-privilege permissions.
- Dedicated test tables and stored procedures that can be safely reset.

## Recommended implementation order

1. Remove the `Condenser.Data` route and any provisional DataCondenser implementation created solely for AzureSql.
2. Remove mock-only AzureSql behavior and tests.
3. Define AzureSql-owned write normalization and immutable-plan behavior.
4. Define and pin the `Microsoft.Data.SqlClient` dependency package layout.
5. Refactor the AzureSql module, class, manifest, factory, and operation helper structure.
6. Implement secure connection construction and authentication modes.
7. Implement typed SQL parameter construction.
8. Implement Write with stored-procedure JSON ingestion.
9. Implement Query with empty and multiple result-set support.
10. Implement Delete with accurate affected-row semantics.
11. Harden JSON conversion for metadata, nulls, dates, binary values, and precision-sensitive numbers.
12. Add transactions, deterministic disposal, sanitized errors, and rollback behavior.
13. Validate the `sdadev01` / `SDAWorkItems` `FusionDatabase` mapping and hydrated `Resource` contract.
14. Update plans, examples, and adapter documentation to use `Data.FusionDatabase`.
15. Run unit, direct mapped-routing, clean-session, and gated live Azure SQL integration tests.
16. Run the existing Foundation mapped-adapter and plan-execution regression suites.

## Completion criteria

The implementation is complete when:

- The production environment resolves `SovereignTrust.Adapters.Data.AzureSql` from the `FusionDatabase` virtual path without manual module import or registration.
- `Data.FusionDatabase` can execute real Write, Query, and Delete operations through the mapped data route.
- SQL text and parameter values remain separate.
- Writes use stored procedures with normalized JSON payloads.
- Query results preserve empty and multiple result sets with metadata.
- Deletes distinguish zero affected rows from an unknown count.
- All successful results are valid JSON text.
- No provider or database objects escape the adapter boundary.
- Failed mutating operations roll back.
- Secrets and access tokens are neither committed nor logged.
- The original caller plan and input remain unchanged.
- Focused integration and existing regression tests pass.
