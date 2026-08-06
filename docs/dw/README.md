# Data Warehouse — Redmine BI

DDL para el destino **SQL Server** del ETL en **SSIS**, alineado al patrón de la cátedra (SK + BK, SCD, `Parametros`).

| Script | Contenido |
|--------|-----------|
| [01_create_dw.sql](01_create_dw.sql) | BD `RedmineDW`, dimensiones, hechos, `Parametros`, miembros `-1`, calendario |
| [02_scd_procedures.sql](02_scd_procedures.sql) | Procedimientos SCD1/SCD2 al estilo de la cátedra |
| [03_ssis_full_load_design.md](03_ssis_full_load_design.md) | Diseño del package SSIS `ETL_Redmine_FullLoad` |

## Ejecución

```powershell
sqlcmd -S localhost -E -i docs\dw\01_create_dw.sql
sqlcmd -S localhost -E -i docs\dw\02_scd_procedures.sql
```

El primero **recrea** las tablas (DROP + CREATE); pensado para laboratorio. El segundo es idempotente (`CREATE OR ALTER`).

## Dimensiones (patrón cátedra)

| Tabla | SK | BK (origen) | SCD |
|-------|----|-------------|-----|
| `DimDate` | `DateKey` = YYYYMMDD (sin IDENTITY) | misma key | N/A (generada) |
| `DimProject` | `ProjectKey` IDENTITY | `ProjectID` ← `projects.id` | Activo / FechaInicio / FechaFin |
| `DimUser` | `UserKey` | `UserID` ← `users.id` | idem |
| `DimIssueStatus` | `StatusKey` | `StatusID` | idem |
| `DimTracker` | `TrackerKey` | `TrackerID` | idem |
| `DimPriority` | `PriorityKey` | `PriorityID` (IssuePriority) | idem |
| `DimActivity` | `ActivityKey` | `ActivityID` (TimeEntryActivity) | idem |
| `DimVersion` | `VersionKey` | `VersionID` ← `versions.id` | idem |
| `DimMember` | `MemberKey` | `MemberRoleID` | idem |
| `DimSeverity` | `SeverityKey` | `SeverityID` | **condicional** |
| `DimSprint` | `SprintKey` | `SprintID` | **condicional** |

Todas las dims de negocio incluyen miembro desconocido **`SK = -1`** (vía `IDENTITY_INSERT`) para mapear nulos del origen en SSIS.

## Hechos

| Tabla | Grano | FKs principales |
|-------|-------|-----------------|
| `FactIssue` | 1 fila / `issues.id` | Project, Tracker, Status, Priority, Version, Severity, Author, Assignee, fechas |
| `FactTimeEntry` | 1 fila / `time_entries.id` | Project, User, Activity, SpentOn; `IssueID` degenerada (nullable) |
| `FactIssueHistory` | 1 fila / `journal_details.id` | User, Date, Old/New Status, Old/New Version |
| `FactBurndownDaily` | Version × día | Version, SnapshotDate, Project |

## Parametros

```sql
SELECT Valor FROM dbo.Parametros WHERE Nombre = 'UltimaFechaEjecucion';
-- valor inicial: 1900-01-01  (full load / primera ejecución)
```

Usar en SSIS para controlar incremental después de la carga inicial.

## Convención de carga SSIS

1. Truncar hechos (o full reload) → cargar dims (lookup BK → SK activa) → cargar hechos.
2. FKs nulas del origen → mapear a SK `-1` (Derived Column) **antes** del Destination.
3. `DateKey` = `YYYYMMDD` a partir de la fecha origen.
4. DimSeverity / DimSprint: cargar solo si pasan validación en Redmine.

## Procedimientos SCD (`02_scd_procedures.sql`)

| Procedimiento | SCD1 | SCD2 |
|---------------|------|------|
| `ActualizarUsuario` | Login, nombres, email, tipo, admin, last login | `StatusCode` |
| `ActualizarProyecto` | Nombre, identificador, descripción, padre, público | `StatusCode` / `StatusName` |
| `ActualizarVersion` | Nombre, descripción, sharing, project | `Status`, `IsOpen`, `EffectiveDate` |
| `ActualizarIssueStatus` | todos | — |
| `ActualizarTracker` | todos | — |
| `ActualizarPriority` | todos | — |
| `ActualizarActivity` | todos | — |
| `ActualizarParametro` | upsert de `Parametros` (cierre de carga SSIS) | — |

En SSIS: Lookup BK → SK activa (`Activo = 1`), luego **OLE DB Command** llamando al `Actualizar*`. Si no hay fila, **OLE DB Destination** (insert de nueva dimensión).

## Package Full Load

Diseño completo: [03_ssis_full_load_design.md](03_ssis_full_load_design.md)

Resumen:

1. Truncar hechos + recargar dims (conservar `SK = -1` y `DimDate`)
2. Dims independientes → Version / Member → FactIssue → FactTimeEntry → FactIssueHistory
3. Lookups BK→SK; nulos → `-1`
4. Validaciones SQL + `ActualizarParametro('UltimaFechaEjecucion')`
5. DimSeverity, DimSprint y FactBurndownDaily fuera de v1

## Pendiente

- Implementar el `.dtsx` en SSDT / Visual Studio
- Package incremental (`Actualizar*` + filtro por `UltimaFechaEjecucion`)
- Staging `stg.*` (opcional)
