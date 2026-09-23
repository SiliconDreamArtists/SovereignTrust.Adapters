# Data.AzureSql

The intended plan route is `Data.FusionDatabase -> MappedDataAdapter -> FusionDatabase -> Data_AzureSql`. The configured virtual path is `SovereignTrust.Adapters.Data.AzureSql.FusionDatabase.Persistent.Full`.

The provisional in-memory implementation and `Condenser.Data` route have been removed. The adapter retains its constructed jacket and returns failed signals for unsupported activities, invalid basic command configuration, and execution until the Azure SQL operations are implemented. The private `Invoke-AzureSqlExecution` function is the internal test seam; it has no public mock configuration or handler registration. Write normalization, provider packaging, connection handling, operations, and deployment tests are scheduled in the implementation plan.
