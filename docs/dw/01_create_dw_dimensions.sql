/*
================================================================================
  DW Redmine BI — DDL de dimensiones (SQL Server)
================================================================================
  Origen de columnas : docs/stm/redmine-stm.xlsx  (generate_stm.py)
  Modelo funcional   : docs/redmine-bi-model.md
  Estrategia         : claves naturales (SCD tipo 1)
  Destino ETL        : Microsoft SSIS → SQL Server

  Incluye:
    - CREATE DATABASE (si no existe)
    - Esquema dim
    - 11 dimensiones (10 del STM + DimActivity, brecha de FactTimeEntry)
    - Miembros desconocidos (-1) para FKs nulas del origen
    - Generacion de DimDate (rango parametrizable)

  Condicionales (tablas creadas; carga SSIS solo si pasan validacion):
    - DimSeverity  → requiere custom field 'Severidad'
    - DimSprint    → requiere plugin redmine_agile

  Uso:
    sqlcmd -S localhost -E -i docs/dw/01_create_dw_dimensions.sql
    -- o ejecutar en SSMS contra la instancia del DW
================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*------------------------------------------------------------------------------
  1. Base de datos
------------------------------------------------------------------------------*/
IF DB_ID(N'RedmineDW') IS NULL
BEGIN
    CREATE DATABASE RedmineDW;
END
GO

USE RedmineDW;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'dim')
    EXEC(N'CREATE SCHEMA dim AUTHORIZATION dbo;');
GO

/*------------------------------------------------------------------------------
  2. DROP (idempotente para recrear en laboratorio)
  Orden inverso a dependencias logicas.
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'dim.DimMember',  N'U') IS NOT NULL DROP TABLE dim.DimMember;
IF OBJECT_ID(N'dim.DimSprint',  N'U') IS NOT NULL DROP TABLE dim.DimSprint;
IF OBJECT_ID(N'dim.DimSeverity',N'U') IS NOT NULL DROP TABLE dim.DimSeverity;
IF OBJECT_ID(N'dim.DimVersion', N'U') IS NOT NULL DROP TABLE dim.DimVersion;
IF OBJECT_ID(N'dim.DimActivity',N'U') IS NOT NULL DROP TABLE dim.DimActivity;
IF OBJECT_ID(N'dim.DimPriority',N'U') IS NOT NULL DROP TABLE dim.DimPriority;
IF OBJECT_ID(N'dim.DimTracker', N'U') IS NOT NULL DROP TABLE dim.DimTracker;
IF OBJECT_ID(N'dim.DimIssueStatus', N'U') IS NOT NULL DROP TABLE dim.DimIssueStatus;
IF OBJECT_ID(N'dim.DimUser',    N'U') IS NOT NULL DROP TABLE dim.DimUser;
IF OBJECT_ID(N'dim.DimProject', N'U') IS NOT NULL DROP TABLE dim.DimProject;
IF OBJECT_ID(N'dim.DimDate',    N'U') IS NOT NULL DROP TABLE dim.DimDate;
GO

/*------------------------------------------------------------------------------
  3. DimDate — calendario generado (no proviene de Redmine)
------------------------------------------------------------------------------*/
CREATE TABLE dim.DimDate
(
    date_key        INT           NOT NULL,          -- YYYYMMDD; -1 = Sin fecha
    [date]          DATE          NULL,              -- NULL solo para el miembro -1
    [year]          INT           NOT NULL,
    [quarter]       TINYINT       NOT NULL,
    month_num       TINYINT       NOT NULL,
    month_name      NVARCHAR(20)  NOT NULL,
    year_month      CHAR(7)       NOT NULL,          -- YYYY-MM
    iso_week        TINYINT       NOT NULL,
    iso_year_week   CHAR(8)       NOT NULL,          -- YYYY-Www
    day_of_month    TINYINT       NOT NULL,
    day_of_week     TINYINT       NOT NULL,          -- 1 = lunes ... 7 = domingo
    day_name        NVARCHAR(20)  NOT NULL,
    is_weekend      BIT           NOT NULL CONSTRAINT DF_DimDate_is_weekend DEFAULT (0),
    is_working_day  BIT           NOT NULL CONSTRAINT DF_DimDate_is_working_day DEFAULT (1),
    CONSTRAINT PK_DimDate PRIMARY KEY CLUSTERED (date_key)
);
GO

/*------------------------------------------------------------------------------
  4. Dimensiones de catalogo (independientes)
------------------------------------------------------------------------------*/
CREATE TABLE dim.DimProject
(
    project_key           INT            NOT NULL,   -- projects.id; -1 = Sin proyecto
    project_name          NVARCHAR(255)  NOT NULL,
    project_identifier    NVARCHAR(255)  NULL,
    project_description   NVARCHAR(1000) NULL,
    parent_project_key    INT            NULL,       -- -1 si no tiene padre
    project_status_code   INT            NOT NULL,
    project_status_name   NVARCHAR(20)   NOT NULL,   -- Activo / Archivado / Cerrado
    is_active             BIT            NOT NULL CONSTRAINT DF_DimProject_is_active DEFAULT (1),
    is_public             BIT            NOT NULL CONSTRAINT DF_DimProject_is_public DEFAULT (0),
    default_version_key   INT            NULL,       -- -1 si no hay default
    created_on            DATETIME2(0)   NULL,
    CONSTRAINT PK_DimProject PRIMARY KEY CLUSTERED (project_key)
);
GO

CREATE TABLE dim.DimUser
(
    user_key        INT            NOT NULL,         -- users.id; -1 = Sin asignar
    login           NVARCHAR(255)  NOT NULL,
    first_name      NVARCHAR(30)   NOT NULL,
    last_name       NVARCHAR(255)  NOT NULL,
    full_name       NVARCHAR(290)  NOT NULL,
    email           NVARCHAR(255)  NULL,
    user_type       NVARCHAR(255)  NULL,             -- User / Group / AnonymousUser
    is_admin        BIT            NOT NULL CONSTRAINT DF_DimUser_is_admin DEFAULT (0),
    status_code     INT            NOT NULL,
    is_active       BIT            NOT NULL CONSTRAINT DF_DimUser_is_active DEFAULT (1),
    last_login_on   DATETIME2(0)   NULL,
    created_on      DATETIME2(0)   NULL,
    CONSTRAINT PK_DimUser PRIMARY KEY CLUSTERED (user_key)
);
GO

CREATE TABLE dim.DimIssueStatus
(
    status_key          INT           NOT NULL,      -- issue_statuses.id; -1 = Sin estado
    status_name         NVARCHAR(30)  NOT NULL,
    status_description  NVARCHAR(255) NULL,
    is_closed           BIT           NOT NULL CONSTRAINT DF_DimIssueStatus_is_closed DEFAULT (0),
    status_position     INT           NULL,
    default_done_ratio  INT           NULL,
    CONSTRAINT PK_DimIssueStatus PRIMARY KEY CLUSTERED (status_key)
);
GO

CREATE TABLE dim.DimTracker
(
    tracker_key           INT           NOT NULL,    -- trackers.id; -1 = Sin tracker
    tracker_name          NVARCHAR(30)  NOT NULL,
    tracker_description   NVARCHAR(255) NULL,
    is_in_roadmap         BIT           NOT NULL CONSTRAINT DF_DimTracker_is_in_roadmap DEFAULT (1),
    tracker_position      INT           NULL,
    default_status_key    INT           NULL,        -- FK logica a DimIssueStatus; -1 si NULL
    CONSTRAINT PK_DimTracker PRIMARY KEY CLUSTERED (tracker_key)
);
GO

CREATE TABLE dim.DimPriority
(
    priority_key      INT          NOT NULL,         -- enumerations.id (IssuePriority); -1 = Sin prioridad
    priority_name     NVARCHAR(30) NOT NULL,
    priority_position INT          NULL,
    is_default        BIT          NOT NULL CONSTRAINT DF_DimPriority_is_default DEFAULT (0),
    is_active         BIT          NOT NULL CONSTRAINT DF_DimPriority_is_active DEFAULT (1),
    CONSTRAINT PK_DimPriority PRIMARY KEY CLUSTERED (priority_key)
);
GO

/*
  DimActivity — no estaba en §3.2 del modelo; FactTimeEntry.activity_key la requiere.
  Fuente: enumerations WHERE type = 'TimeEntryActivity'
*/
CREATE TABLE dim.DimActivity
(
    activity_key      INT          NOT NULL,         -- enumerations.id; -1 = Sin actividad
    activity_name     NVARCHAR(30) NOT NULL,
    activity_position INT          NULL,
    is_default        BIT          NOT NULL CONSTRAINT DF_DimActivity_is_default DEFAULT (0),
    is_active         BIT          NOT NULL CONSTRAINT DF_DimActivity_is_active DEFAULT (1),
    CONSTRAINT PK_DimActivity PRIMARY KEY CLUSTERED (activity_key)
);
GO

/*------------------------------------------------------------------------------
  5. Dimensiones dependientes / puente
------------------------------------------------------------------------------*/
CREATE TABLE dim.DimVersion
(
    version_key          INT           NOT NULL,     -- versions.id; -1 = Sin version
    project_key          INT           NOT NULL,     -- versions.project_id; -1 en miembro desconocido
    version_name         NVARCHAR(255) NOT NULL,
    version_description  NVARCHAR(255) NULL,
    effective_date       DATE          NULL,
    version_status       NVARCHAR(20)  NULL,         -- open / locked / closed
    is_open              BIT           NOT NULL CONSTRAINT DF_DimVersion_is_open DEFAULT (1),
    sharing              NVARCHAR(20)  NOT NULL CONSTRAINT DF_DimVersion_sharing DEFAULT (N'none'),
    created_on           DATETIME2(0)  NULL,
    CONSTRAINT PK_DimVersion PRIMARY KEY CLUSTERED (version_key)
);
GO

/*
  DimSeverity — CONDICIONAL.
  Cargar solo si existe custom_fields.name = 'Severidad'.
*/
CREATE TABLE dim.DimSeverity
(
    severity_key       INT           NOT NULL,       -- custom_field_enumerations.id; -1 = Sin severidad
    custom_field_key   INT           NOT NULL,
    severity_name      NVARCHAR(255) NOT NULL,
    severity_position  INT           NOT NULL,
    is_active          BIT           NOT NULL CONSTRAINT DF_DimSeverity_is_active DEFAULT (1),
    CONSTRAINT PK_DimSeverity PRIMARY KEY CLUSTERED (severity_key)
);
GO

/*
  DimMember — tabla puente (usuario × proyecto × rol).
  Grano: member_roles.id
*/
CREATE TABLE dim.DimMember
(
    member_role_key     INT            NOT NULL,     -- member_roles.id
    member_key          INT            NOT NULL,     -- members.id
    user_key            INT            NOT NULL,
    project_key         INT            NOT NULL,
    role_key            INT            NOT NULL,
    role_name           NVARCHAR(255)  NOT NULL,
    is_builtin_role     BIT            NOT NULL CONSTRAINT DF_DimMember_is_builtin DEFAULT (0),
    is_inherited        BIT            NOT NULL CONSTRAINT DF_DimMember_is_inherited DEFAULT (0),
    member_created_on   DATETIME2(0)   NULL,
    CONSTRAINT PK_DimMember PRIMARY KEY CLUSTERED (member_role_key)
);
GO

/*
  DimSprint — CONDICIONAL (plugin redmine_agile).
  Cargar solo si SHOW TABLES LIKE 'agile%' devuelve filas.
  Nombres de columna origen a confirmar tras instalar el plugin.
*/
CREATE TABLE dim.DimSprint
(
    sprint_key     INT           NOT NULL,           -- agile_sprints.id; -1 = Sin sprint
    project_key    INT           NOT NULL,
    sprint_name    NVARCHAR(255) NOT NULL,
    start_date     DATE          NULL,
    end_date       DATE          NULL,
    sprint_status  NVARCHAR(20)  NULL,
    CONSTRAINT PK_DimSprint PRIMARY KEY CLUSTERED (sprint_key)
);
GO

/*------------------------------------------------------------------------------
  6. Indices de apoyo (atributos de busqueda / slicers)
------------------------------------------------------------------------------*/
CREATE NONCLUSTERED INDEX IX_DimProject_identifier ON dim.DimProject (project_identifier);
CREATE NONCLUSTERED INDEX IX_DimUser_login         ON dim.DimUser (login);
CREATE NONCLUSTERED INDEX IX_DimUser_full_name     ON dim.DimUser (full_name);
CREATE NONCLUSTERED INDEX IX_DimVersion_project    ON dim.DimVersion (project_key);
CREATE NONCLUSTERED INDEX IX_DimMember_user        ON dim.DimMember (user_key);
CREATE NONCLUSTERED INDEX IX_DimMember_project     ON dim.DimMember (project_key);
CREATE NONCLUSTERED INDEX IX_DimDate_year_month    ON dim.DimDate (year_month);
CREATE NONCLUSTERED INDEX IX_DimDate_iso_year_week ON dim.DimDate (iso_year_week);
GO

/*------------------------------------------------------------------------------
  7. Miembros desconocidos (-1)
  Convención: las FKs nulas del origen se mapean a -1 en SSIS (Derived Column).
------------------------------------------------------------------------------*/
INSERT INTO dim.DimDate
(
    date_key, [date], [year], [quarter], month_num, month_name, year_month,
    iso_week, iso_year_week, day_of_month, day_of_week, day_name,
    is_weekend, is_working_day
)
VALUES
(
    -1, NULL, 0, 0, 0, N'Sin fecha', N'0000-00',
    0, N'0000-W00', 0, 0, N'Sin fecha',
    0, 0
);

INSERT INTO dim.DimProject
(
    project_key, project_name, project_identifier, project_description,
    parent_project_key, project_status_code, project_status_name,
    is_active, is_public, default_version_key, created_on
)
VALUES
(
    -1, N'Sin proyecto', N'unknown', NULL,
    -1, 0, N'Desconocido',
    0, 0, -1, NULL
);

INSERT INTO dim.DimUser
(
    user_key, login, first_name, last_name, full_name, email, user_type,
    is_admin, status_code, is_active, last_login_on, created_on
)
VALUES
(
    -1, N'unknown', N'Sin', N'asignar', N'Sin asignar', NULL, N'Unknown',
    0, 0, 0, NULL, NULL
);

INSERT INTO dim.DimIssueStatus
(
    status_key, status_name, status_description, is_closed, status_position, default_done_ratio
)
VALUES
(
    -1, N'Sin estado', NULL, 0, 0, NULL
);

INSERT INTO dim.DimTracker
(
    tracker_key, tracker_name, tracker_description, is_in_roadmap, tracker_position, default_status_key
)
VALUES
(
    -1, N'Sin tracker', NULL, 0, 0, -1
);

INSERT INTO dim.DimPriority
(
    priority_key, priority_name, priority_position, is_default, is_active
)
VALUES
(
    -1, N'Sin prioridad', 0, 0, 0
);

INSERT INTO dim.DimActivity
(
    activity_key, activity_name, activity_position, is_default, is_active
)
VALUES
(
    -1, N'Sin actividad', 0, 0, 0
);

INSERT INTO dim.DimVersion
(
    version_key, project_key, version_name, version_description,
    effective_date, version_status, is_open, sharing, created_on
)
VALUES
(
    -1, -1, N'Sin version', NULL,
    NULL, N'unknown', 0, N'none', NULL
);

INSERT INTO dim.DimSeverity
(
    severity_key, custom_field_key, severity_name, severity_position, is_active
)
VALUES
(
    -1, -1, N'Sin severidad', 0, 0
);

INSERT INTO dim.DimSprint
(
    sprint_key, project_key, sprint_name, start_date, end_date, sprint_status
)
VALUES
(
    -1, -1, N'Sin sprint', NULL, NULL, N'unknown'
);
GO

/*------------------------------------------------------------------------------
  8. Generacion de DimDate
  Rango por defecto: 2020-01-01 → hoy + 1 año.
  Ajustar @StartDate / @EndDate segun MIN(issues.created_on) del origen.
------------------------------------------------------------------------------*/
DECLARE @StartDate DATE = '2020-01-01';
DECLARE @EndDate   DATE = DATEADD(YEAR, 1, CAST(GETDATE() AS DATE));
DECLARE @d         DATE = @StartDate;

WHILE @d <= @EndDate
BEGIN
    DECLARE @date_key INT = YEAR(@d) * 10000 + MONTH(@d) * 100 + DAY(@d);
    DECLARE @dow TINYINT = ((DATEPART(WEEKDAY, @d) + @@DATEFIRST - 2) % 7) + 1; -- 1=lunes
    -- ISO week (aproximacion SQL Server: DATEPART(ISO_WEEK, ...))
    DECLARE @iso_week TINYINT = DATEPART(ISO_WEEK, @d);
    DECLARE @iso_year INT = YEAR(@d);
    -- Ajuste de año ISO en bordes de año
    IF @iso_week >= 52 AND MONTH(@d) = 1 SET @iso_year = YEAR(@d) - 1;
    IF @iso_week = 1 AND MONTH(@d) = 12 SET @iso_year = YEAR(@d) + 1;

    INSERT INTO dim.DimDate
    (
        date_key, [date], [year], [quarter], month_num, month_name, year_month,
        iso_week, iso_year_week, day_of_month, day_of_week, day_name,
        is_weekend, is_working_day
    )
    VALUES
    (
        @date_key,
        @d,
        YEAR(@d),
        DATEPART(QUARTER, @d),
        MONTH(@d),
        DATENAME(MONTH, @d),
        FORMAT(@d, 'yyyy-MM'),
        @iso_week,
        CONCAT(FORMAT(@iso_year, '0000'), '-W', FORMAT(@iso_week, '00')),
        DAY(@d),
        @dow,
        DATENAME(WEEKDAY, @d),
        CASE WHEN @dow IN (6, 7) THEN 1 ELSE 0 END,
        CASE WHEN @dow IN (6, 7) THEN 0 ELSE 1 END
    );

    SET @d = DATEADD(DAY, 1, @d);
END
GO

/*------------------------------------------------------------------------------
  9. Verificacion rapida
------------------------------------------------------------------------------*/
SELECT s.name AS [schema], t.name AS [table], SUM(p.rows) AS [rows]
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE s.name = N'dim'
GROUP BY s.name, t.name
ORDER BY t.name;
GO

PRINT N'OK: RedmineDW.dim.* creado con miembros -1 y DimDate poblada.';
GO
