# Data Warehouse — Redmine BI

Scripts DDL para el destino SQL Server del ETL en **SSIS**.

| Script | Contenido |
|--------|-----------|
| [01_create_dw_dimensions.sql](01_create_dw_dimensions.sql) | BD `RedmineDW`, esquema `dim`, 11 dimensiones, miembros `-1`, calendario |

## Dimensiones

| Tabla | Origen | Notas |
|-------|--------|-------|
| `dim.DimDate` | Generada | Rango 2020 → hoy+1 año; `date_key = -1` Sin fecha |
| `dim.DimProject` | `projects` | Clave natural |
| `dim.DimUser` | `users` + `email_addresses` | Sin campos de autenticación |
| `dim.DimIssueStatus` | `issue_statuses` | Define `is_closed` |
| `dim.DimTracker` | `trackers` | |
| `dim.DimPriority` | `enumerations` (IssuePriority) | Proxy de severidad |
| `dim.DimActivity` | `enumerations` (TimeEntryActivity) | Completa brecha del modelo §3.2 |
| `dim.DimVersion` | `versions` | Sprint nativo por defecto |
| `dim.DimMember` | `members` + `member_roles` + `roles` | Puente |
| `dim.DimSeverity` | custom fields | **Condicional** |
| `dim.DimSprint` | plugin Agile | **Condicional** |

## Ejecución

En SSMS o `sqlcmd`, contra la instancia del DW:

```sql
-- Revisar/ajustar @StartDate y @EndDate dentro del script si hace falta
```

```powershell
sqlcmd -S localhost -E -i docs\dw\01_create_dw_dimensions.sql
```

## Convención `-1`

En SSIS, mapear FKs nulas del origen a `-1` con Derived Column antes del Lookup / Destination. Los miembros desconocidos ya están insertados.

## Pendiente

- DDL de hechos (`fact.*`) y staging (`stg.*`)
- FKs físicas dim→fact (opcional; muchos DW las omiten y validan en ETL)
