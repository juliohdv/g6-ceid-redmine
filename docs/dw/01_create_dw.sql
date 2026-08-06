/*
================================================================================
  DW Redmine BI — DDL completo (SQL Server)
================================================================================
  Alineado al patrón de la cátedra (script DWVentas):
    - Llave surrogada (SK) IDENTITY en dimensiones de negocio
    - Llave de negocio (BK) = ID del origen Redmine
    - SCD: Activo, FechaInicio, FechaFin
    - DimDate con key ISO YYYYMMDD (sin IDENTITY), como DimTiempo
    - Tabla Parametros (UltimaFechaEjecucion) para cargas SSIS
    - Hechos con FK físicas a las SK de las dimensiones

  Origen de columnas : docs/stm/redmine-stm.xlsx
  Modelo funcional   : docs/redmine-bi-model.md
  Destino ETL        : Microsoft SSIS → SQL Server

  Dimensiones:
    DimDate, DimProject, DimUser, DimIssueStatus, DimTracker,
    DimPriority, DimActivity, DimVersion, DimSeverity, DimMember, DimSprint

  Hechos:
    FactIssue, FactTimeEntry, FactIssueHistory, FactBurndownDaily

  Condicionales (tabla creada; carga SSIS solo si validan):
    DimSeverity → custom field 'Severidad'
    DimSprint   → plugin redmine_agile

  Uso:
    sqlcmd -S localhost -E -i docs/dw/01_create_dw.sql
================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*==============================================================================
  1. Base de datos
==============================================================================*/
IF DB_ID(N'RedmineDW') IS NULL
BEGIN
    CREATE DATABASE RedmineDW;
END
GO

USE RedmineDW;
GO

/*==============================================================================
  2. DROP (laboratorio / recreación limpia)
  Orden: hechos → dims dependientes → dims independientes → Parametros
==============================================================================*/
IF OBJECT_ID(N'dbo.FactBurndownDaily', N'U') IS NOT NULL DROP TABLE dbo.FactBurndownDaily;
IF OBJECT_ID(N'dbo.FactIssueHistory',  N'U') IS NOT NULL DROP TABLE dbo.FactIssueHistory;
IF OBJECT_ID(N'dbo.FactTimeEntry',     N'U') IS NOT NULL DROP TABLE dbo.FactTimeEntry;
IF OBJECT_ID(N'dbo.FactIssue',         N'U') IS NOT NULL DROP TABLE dbo.FactIssue;

IF OBJECT_ID(N'dbo.DimMember',         N'U') IS NOT NULL DROP TABLE dbo.DimMember;
IF OBJECT_ID(N'dbo.DimSprint',         N'U') IS NOT NULL DROP TABLE dbo.DimSprint;
IF OBJECT_ID(N'dbo.DimSeverity',       N'U') IS NOT NULL DROP TABLE dbo.DimSeverity;
IF OBJECT_ID(N'dbo.DimVersion',        N'U') IS NOT NULL DROP TABLE dbo.DimVersion;
IF OBJECT_ID(N'dbo.DimActivity',       N'U') IS NOT NULL DROP TABLE dbo.DimActivity;
IF OBJECT_ID(N'dbo.DimPriority',       N'U') IS NOT NULL DROP TABLE dbo.DimPriority;
IF OBJECT_ID(N'dbo.DimTracker',        N'U') IS NOT NULL DROP TABLE dbo.DimTracker;
IF OBJECT_ID(N'dbo.DimIssueStatus',    N'U') IS NOT NULL DROP TABLE dbo.DimIssueStatus;
IF OBJECT_ID(N'dbo.DimUser',           N'U') IS NOT NULL DROP TABLE dbo.DimUser;
IF OBJECT_ID(N'dbo.DimProject',        N'U') IS NOT NULL DROP TABLE dbo.DimProject;
IF OBJECT_ID(N'dbo.DimDate',           N'U') IS NOT NULL DROP TABLE dbo.DimDate;

IF OBJECT_ID(N'dbo.Parametros',        N'U') IS NOT NULL DROP TABLE dbo.Parametros;

-- Limpieza de versión anterior con esquema dim (si existía)
IF OBJECT_ID(N'dim.DimMember', N'U') IS NOT NULL DROP TABLE dim.DimMember;
IF OBJECT_ID(N'dim.DimSprint', N'U') IS NOT NULL DROP TABLE dim.DimSprint;
IF OBJECT_ID(N'dim.DimSeverity', N'U') IS NOT NULL DROP TABLE dim.DimSeverity;
IF OBJECT_ID(N'dim.DimVersion', N'U') IS NOT NULL DROP TABLE dim.DimVersion;
IF OBJECT_ID(N'dim.DimActivity', N'U') IS NOT NULL DROP TABLE dim.DimActivity;
IF OBJECT_ID(N'dim.DimPriority', N'U') IS NOT NULL DROP TABLE dim.DimPriority;
IF OBJECT_ID(N'dim.DimTracker', N'U') IS NOT NULL DROP TABLE dim.DimTracker;
IF OBJECT_ID(N'dim.DimIssueStatus', N'U') IS NOT NULL DROP TABLE dim.DimIssueStatus;
IF OBJECT_ID(N'dim.DimUser', N'U') IS NOT NULL DROP TABLE dim.DimUser;
IF OBJECT_ID(N'dim.DimProject', N'U') IS NOT NULL DROP TABLE dim.DimProject;
IF OBJECT_ID(N'dim.DimDate', N'U') IS NOT NULL DROP TABLE dim.DimDate;
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'dim')
    EXEC(N'DROP SCHEMA dim;');
GO

/*==============================================================================
  3. DIMENSIONES
==============================================================================*/

------------------------------------------------------------------------------
-- DimDate (equivalente a DimTiempo del ejemplo de cátedra)
-- SK = BK = YYYYMMDD; NO es IDENTITY.
------------------------------------------------------------------------------
CREATE TABLE dbo.DimDate
(
    DateKey         INT           NOT NULL,          -- YYYYMMDD; -1 = Sin fecha
    Fecha           DATE          NULL,              -- NULL solo para miembro -1
    Anio            SMALLINT      NOT NULL,
    Trimestre       TINYINT       NOT NULL,
    Mes             TINYINT       NOT NULL,
    NombreMes       NVARCHAR(20)  NOT NULL,
    AnioMes         CHAR(7)       NOT NULL,          -- YYYY-MM
    SemanaISO       TINYINT       NOT NULL,
    AnioSemanaISO   CHAR(8)       NOT NULL,          -- YYYY-Www
    Dia             TINYINT       NOT NULL,
    DiaSemana       TINYINT       NOT NULL,          -- 1 = lunes ... 7 = domingo
    NombreDia       NVARCHAR(20)  NOT NULL,
    EsFinDeSemana   BIT           NOT NULL CONSTRAINT DF_DimDate_EsFinDeSemana DEFAULT (0),
    EsDiaHabil      BIT           NOT NULL CONSTRAINT DF_DimDate_EsDiaHabil DEFAULT (1),
    CONSTRAINT PK_DimDate PRIMARY KEY CLUSTERED (DateKey)
);
GO

------------------------------------------------------------------------------
-- DimProject
-- BK = projects.id
------------------------------------------------------------------------------
CREATE TABLE dbo.DimProject
(
    ProjectKey            INT            NOT NULL IDENTITY(1, 1),  -- SK
    ProjectID             INT            NOT NULL,                 -- BK
    Nombre                NVARCHAR(255)  NOT NULL,
    Identificador         NVARCHAR(255)  NULL,
    Descripcion           NVARCHAR(1000) NULL,
    ParentProjectID       INT            NULL,
    StatusCode            INT            NOT NULL,
    StatusName            NVARCHAR(20)   NOT NULL,                 -- Activo/Archivado/Cerrado
    EsPublico             BIT            NOT NULL CONSTRAINT DF_DimProject_EsPublico DEFAULT (0),
    DefaultVersionID      INT            NULL,
    CreatedOn             DATETIME2(0)   NULL,
    -- SCD
    Activo                BIT            NOT NULL CONSTRAINT DF_DimProject_Activo DEFAULT (1),
    FechaInicio           DATETIME       NOT NULL CONSTRAINT DF_DimProject_FechaInicio DEFAULT (GETDATE()),
    FechaFin              DATETIME       NULL,
    CONSTRAINT PK_DimProject PRIMARY KEY CLUSTERED (ProjectKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimProject_BK_Activo
    ON dbo.DimProject (ProjectID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimUser (role-playing: Author / Assignee)
-- BK = users.id  |  NO incluir hashed_password, salt, twofa_*
------------------------------------------------------------------------------
CREATE TABLE dbo.DimUser
(
    UserKey         INT            NOT NULL IDENTITY(1, 1),
    UserID          INT            NOT NULL,                 -- BK
    Login           NVARCHAR(255)  NOT NULL,
    FirstName       NVARCHAR(30)   NOT NULL,
    LastName        NVARCHAR(255)  NOT NULL,
    FullName        NVARCHAR(290)  NOT NULL,
    Email           NVARCHAR(255)  NULL,
    UserType        NVARCHAR(255)  NULL,                     -- User / Group / ...
    EsAdmin         BIT            NOT NULL CONSTRAINT DF_DimUser_EsAdmin DEFAULT (0),
    StatusCode      INT            NOT NULL,
    LastLoginOn     DATETIME2(0)   NULL,
    CreatedOn       DATETIME2(0)   NULL,
    -- SCD
    Activo          BIT            NOT NULL CONSTRAINT DF_DimUser_Activo DEFAULT (1),
    FechaInicio     DATETIME       NOT NULL CONSTRAINT DF_DimUser_FechaInicio DEFAULT (GETDATE()),
    FechaFin        DATETIME       NULL,
    CONSTRAINT PK_DimUser PRIMARY KEY CLUSTERED (UserKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimUser_BK_Activo
    ON dbo.DimUser (UserID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimIssueStatus
-- BK = issue_statuses.id
------------------------------------------------------------------------------
CREATE TABLE dbo.DimIssueStatus
(
    StatusKey           INT           NOT NULL IDENTITY(1, 1),
    StatusID            INT           NOT NULL,                 -- BK
    Nombre              NVARCHAR(30)  NOT NULL,
    Descripcion         NVARCHAR(255) NULL,
    IsClosed            BIT           NOT NULL CONSTRAINT DF_DimIssueStatus_IsClosed DEFAULT (0),
    Posicion            INT           NULL,
    DefaultDoneRatio    INT           NULL,
    -- SCD
    Activo              BIT           NOT NULL CONSTRAINT DF_DimIssueStatus_Activo DEFAULT (1),
    FechaInicio         DATETIME      NOT NULL CONSTRAINT DF_DimIssueStatus_FechaInicio DEFAULT (GETDATE()),
    FechaFin            DATETIME      NULL,
    CONSTRAINT PK_DimIssueStatus PRIMARY KEY CLUSTERED (StatusKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimIssueStatus_BK_Activo
    ON dbo.DimIssueStatus (StatusID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimTracker
-- BK = trackers.id
------------------------------------------------------------------------------
CREATE TABLE dbo.DimTracker
(
    TrackerKey          INT           NOT NULL IDENTITY(1, 1),
    TrackerID           INT           NOT NULL,                 -- BK
    Nombre              NVARCHAR(30)  NOT NULL,
    Descripcion         NVARCHAR(255) NULL,
    IsInRoadmap         BIT           NOT NULL CONSTRAINT DF_DimTracker_IsInRoadmap DEFAULT (1),
    Posicion            INT           NULL,
    DefaultStatusID     INT           NULL,
    -- SCD
    Activo              BIT           NOT NULL CONSTRAINT DF_DimTracker_Activo DEFAULT (1),
    FechaInicio         DATETIME      NOT NULL CONSTRAINT DF_DimTracker_FechaInicio DEFAULT (GETDATE()),
    FechaFin            DATETIME      NULL,
    CONSTRAINT PK_DimTracker PRIMARY KEY CLUSTERED (TrackerKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimTracker_BK_Activo
    ON dbo.DimTracker (TrackerID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimPriority  (enumerations WHERE type = 'IssuePriority')
-- BK = enumerations.id
------------------------------------------------------------------------------
CREATE TABLE dbo.DimPriority
(
    PriorityKey     INT          NOT NULL IDENTITY(1, 1),
    PriorityID      INT          NOT NULL,                     -- BK
    Nombre          NVARCHAR(30) NOT NULL,
    Posicion        INT          NULL,
    IsDefault       BIT          NOT NULL CONSTRAINT DF_DimPriority_IsDefault DEFAULT (0),
    -- SCD
    Activo          BIT          NOT NULL CONSTRAINT DF_DimPriority_Activo DEFAULT (1),
    FechaInicio     DATETIME     NOT NULL CONSTRAINT DF_DimPriority_FechaInicio DEFAULT (GETDATE()),
    FechaFin        DATETIME     NULL,
    CONSTRAINT PK_DimPriority PRIMARY KEY CLUSTERED (PriorityKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimPriority_BK_Activo
    ON dbo.DimPriority (PriorityID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimActivity (enumerations WHERE type = 'TimeEntryActivity')
-- Completa la brecha del modelo §3.2 / FactTimeEntry.ActivityKey
------------------------------------------------------------------------------
CREATE TABLE dbo.DimActivity
(
    ActivityKey     INT          NOT NULL IDENTITY(1, 1),
    ActivityID      INT          NOT NULL,                     -- BK
    Nombre          NVARCHAR(30) NOT NULL,
    Posicion        INT          NULL,
    IsDefault       BIT          NOT NULL CONSTRAINT DF_DimActivity_IsDefault DEFAULT (0),
    -- SCD
    Activo          BIT          NOT NULL CONSTRAINT DF_DimActivity_Activo DEFAULT (1),
    FechaInicio     DATETIME     NOT NULL CONSTRAINT DF_DimActivity_FechaInicio DEFAULT (GETDATE()),
    FechaFin        DATETIME     NULL,
    CONSTRAINT PK_DimActivity PRIMARY KEY CLUSTERED (ActivityKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimActivity_BK_Activo
    ON dbo.DimActivity (ActivityID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimVersion (sprint/release nativo)
-- BK = versions.id
------------------------------------------------------------------------------
CREATE TABLE dbo.DimVersion
(
    VersionKey      INT           NOT NULL IDENTITY(1, 1),
    VersionID       INT           NOT NULL,                     -- BK
    ProjectID       INT           NOT NULL,                     -- BK del proyecto dueño
    Nombre          NVARCHAR(255) NOT NULL,
    Descripcion     NVARCHAR(255) NULL,
    EffectiveDate   DATE          NULL,
    Status          NVARCHAR(20)  NULL,                         -- open / locked / closed
    IsOpen          BIT           NOT NULL CONSTRAINT DF_DimVersion_IsOpen DEFAULT (1),
    Sharing         NVARCHAR(20)  NOT NULL CONSTRAINT DF_DimVersion_Sharing DEFAULT (N'none'),
    CreatedOn       DATETIME2(0)  NULL,
    -- SCD
    Activo          BIT           NOT NULL CONSTRAINT DF_DimVersion_Activo DEFAULT (1),
    FechaInicio     DATETIME      NOT NULL CONSTRAINT DF_DimVersion_FechaInicio DEFAULT (GETDATE()),
    FechaFin        DATETIME      NULL,
    CONSTRAINT PK_DimVersion PRIMARY KEY CLUSTERED (VersionKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimVersion_BK_Activo
    ON dbo.DimVersion (VersionID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimSeverity (CONDICIONAL — custom field 'Severidad')
------------------------------------------------------------------------------
CREATE TABLE dbo.DimSeverity
(
    SeverityKey       INT           NOT NULL IDENTITY(1, 1),
    SeverityID        INT           NOT NULL,                   -- BK (custom_field_enumerations.id)
    CustomFieldID     INT           NOT NULL,
    Nombre            NVARCHAR(255) NOT NULL,
    Posicion          INT           NOT NULL,
    -- SCD
    Activo            BIT           NOT NULL CONSTRAINT DF_DimSeverity_Activo DEFAULT (1),
    FechaInicio       DATETIME      NOT NULL CONSTRAINT DF_DimSeverity_FechaInicio DEFAULT (GETDATE()),
    FechaFin          DATETIME      NULL,
    CONSTRAINT PK_DimSeverity PRIMARY KEY CLUSTERED (SeverityKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimSeverity_BK_Activo
    ON dbo.DimSeverity (SeverityID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimMember (puente usuario × proyecto × rol)
-- BK = member_roles.id
------------------------------------------------------------------------------
CREATE TABLE dbo.DimMember
(
    MemberKey         INT            NOT NULL IDENTITY(1, 1),   -- SK
    MemberRoleID      INT            NOT NULL,                  -- BK
    MemberID          INT            NOT NULL,                  -- members.id
    UserID            INT            NOT NULL,                  -- BK usuario
    ProjectID         INT            NOT NULL,                  -- BK proyecto
    RoleID            INT            NOT NULL,
    RoleName          NVARCHAR(255)  NOT NULL,
    IsBuiltinRole     BIT            NOT NULL CONSTRAINT DF_DimMember_IsBuiltin DEFAULT (0),
    IsInherited       BIT            NOT NULL CONSTRAINT DF_DimMember_IsInherited DEFAULT (0),
    MemberCreatedOn   DATETIME2(0)   NULL,
    -- SCD
    Activo            BIT            NOT NULL CONSTRAINT DF_DimMember_Activo DEFAULT (1),
    FechaInicio       DATETIME       NOT NULL CONSTRAINT DF_DimMember_FechaInicio DEFAULT (GETDATE()),
    FechaFin          DATETIME       NULL,
    CONSTRAINT PK_DimMember PRIMARY KEY CLUSTERED (MemberKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimMember_BK_Activo
    ON dbo.DimMember (MemberRoleID, Activo)
    WHERE Activo = 1;
GO

------------------------------------------------------------------------------
-- DimSprint (CONDICIONAL — plugin redmine_agile)
------------------------------------------------------------------------------
CREATE TABLE dbo.DimSprint
(
    SprintKey       INT           NOT NULL IDENTITY(1, 1),
    SprintID        INT           NOT NULL,                     -- BK
    ProjectID       INT           NOT NULL,
    Nombre          NVARCHAR(255) NOT NULL,
    StartDate       DATE          NULL,
    EndDate         DATE          NULL,
    Status          NVARCHAR(20)  NULL,
    -- SCD
    Activo          BIT           NOT NULL CONSTRAINT DF_DimSprint_Activo DEFAULT (1),
    FechaInicio     DATETIME      NOT NULL CONSTRAINT DF_DimSprint_FechaInicio DEFAULT (GETDATE()),
    FechaFin        DATETIME      NULL,
    CONSTRAINT PK_DimSprint PRIMARY KEY CLUSTERED (SprintKey)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_DimSprint_BK_Activo
    ON dbo.DimSprint (SprintID, Activo)
    WHERE Activo = 1;
GO

/*==============================================================================
  4. TABLAS DE HECHOS
==============================================================================*/

------------------------------------------------------------------------------
-- FactIssue
-- Grano: una fila por issues.id (IssueID degenerada)
------------------------------------------------------------------------------
CREATE TABLE dbo.FactIssue
(
    IssueID                 INT             NOT NULL,           -- degenerada / BK origen
    ProjectKey              INT             NOT NULL,
    TrackerKey              INT             NOT NULL,
    StatusKey               INT             NOT NULL,
    PriorityKey             INT             NOT NULL,
    VersionKey              INT             NOT NULL,           -- -1 SK si sin versión
    SeverityKey             INT             NOT NULL,           -- -1 SK si sin severidad
    AuthorKey               INT             NOT NULL,
    AssigneeKey             INT             NOT NULL,           -- -1 SK si sin asignar
    CreatedDateKey          INT             NOT NULL,
    DueDateKey              INT             NOT NULL,           -- -1 si NULL
    ClosedDateKey           INT             NOT NULL,           -- -1 si abierto
    IssueSubject            NVARCHAR(255)   NOT NULL,
    ParentIssueID           INT             NULL,
    IsRootIssue             BIT             NOT NULL CONSTRAINT DF_FactIssue_IsRoot DEFAULT (1),
    IsPrivate               BIT             NOT NULL CONSTRAINT DF_FactIssue_IsPrivate DEFAULT (0),
    IsClosed                BIT             NOT NULL CONSTRAINT DF_FactIssue_IsClosed DEFAULT (0),
    EstimatedHours          DECIMAL(9, 2)   NULL,
    DoneRatio               INT             NOT NULL CONSTRAINT DF_FactIssue_DoneRatio DEFAULT (0),
    ActualHours             DECIMAL(9, 2)   NOT NULL CONSTRAINT DF_FactIssue_ActualHours DEFAULT (0),
    HoursVariance           DECIMAL(9, 2)   NULL,
    HoursVariancePct        DECIMAL(9, 4)   NULL,
    ScheduleVarianceDays    INT             NULL,
    RemainingHours          DECIMAL(9, 2)   NULL,
    OpenIssueCount          INT             NOT NULL CONSTRAINT DF_FactIssue_OpenCount DEFAULT (0),
    CONSTRAINT PK_FactIssue PRIMARY KEY CLUSTERED (IssueID),
    CONSTRAINT FK_FactIssue_Project   FOREIGN KEY (ProjectKey)     REFERENCES dbo.DimProject (ProjectKey),
    CONSTRAINT FK_FactIssue_Tracker   FOREIGN KEY (TrackerKey)     REFERENCES dbo.DimTracker (TrackerKey),
    CONSTRAINT FK_FactIssue_Status    FOREIGN KEY (StatusKey)      REFERENCES dbo.DimIssueStatus (StatusKey),
    CONSTRAINT FK_FactIssue_Priority  FOREIGN KEY (PriorityKey)    REFERENCES dbo.DimPriority (PriorityKey),
    CONSTRAINT FK_FactIssue_Version   FOREIGN KEY (VersionKey)     REFERENCES dbo.DimVersion (VersionKey),
    CONSTRAINT FK_FactIssue_Severity  FOREIGN KEY (SeverityKey)    REFERENCES dbo.DimSeverity (SeverityKey),
    CONSTRAINT FK_FactIssue_Author    FOREIGN KEY (AuthorKey)      REFERENCES dbo.DimUser (UserKey),
    CONSTRAINT FK_FactIssue_Assignee  FOREIGN KEY (AssigneeKey)    REFERENCES dbo.DimUser (UserKey),
    CONSTRAINT FK_FactIssue_Created   FOREIGN KEY (CreatedDateKey) REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactIssue_Due       FOREIGN KEY (DueDateKey)     REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactIssue_Closed    FOREIGN KEY (ClosedDateKey)  REFERENCES dbo.DimDate (DateKey)
);
GO

CREATE NONCLUSTERED INDEX IX_FactIssue_Project  ON dbo.FactIssue (ProjectKey);
CREATE NONCLUSTERED INDEX IX_FactIssue_Version  ON dbo.FactIssue (VersionKey);
CREATE NONCLUSTERED INDEX IX_FactIssue_Closed   ON dbo.FactIssue (ClosedDateKey) WHERE IsClosed = 1;
GO

------------------------------------------------------------------------------
-- FactTimeEntry
-- Grano: una fila por time_entries.id
-- IssueID es degenerada (nullable): horas sin tarea → IssueID NULL
------------------------------------------------------------------------------
CREATE TABLE dbo.FactTimeEntry
(
    TimeEntryID         INT             NOT NULL,               -- BK origen
    ProjectKey          INT             NOT NULL,
    IssueID             INT             NULL,                   -- degenerada; NULL = sin issue
    UserKey             INT             NOT NULL,
    ActivityKey         INT             NOT NULL,
    SpentOnDateKey      INT             NOT NULL,
    Hours               DECIMAL(9, 2)   NOT NULL,
    EntryComments       NVARCHAR(1024)  NULL,
    CONSTRAINT PK_FactTimeEntry PRIMARY KEY CLUSTERED (TimeEntryID),
    CONSTRAINT FK_FactTimeEntry_Project  FOREIGN KEY (ProjectKey)     REFERENCES dbo.DimProject (ProjectKey),
    CONSTRAINT FK_FactTimeEntry_User     FOREIGN KEY (UserKey)        REFERENCES dbo.DimUser (UserKey),
    CONSTRAINT FK_FactTimeEntry_Activity FOREIGN KEY (ActivityKey)    REFERENCES dbo.DimActivity (ActivityKey),
    CONSTRAINT FK_FactTimeEntry_SpentOn  FOREIGN KEY (SpentOnDateKey) REFERENCES dbo.DimDate (DateKey)
);
GO

CREATE NONCLUSTERED INDEX IX_FactTimeEntry_Project ON dbo.FactTimeEntry (ProjectKey);
CREATE NONCLUSTERED INDEX IX_FactTimeEntry_Issue   ON dbo.FactTimeEntry (IssueID);
CREATE NONCLUSTERED INDEX IX_FactTimeEntry_SpentOn ON dbo.FactTimeEntry (SpentOnDateKey);
GO

------------------------------------------------------------------------------
-- FactIssueHistory
-- Grano: una fila por journal_details.id (cambios relevantes)
------------------------------------------------------------------------------
CREATE TABLE dbo.FactIssueHistory
(
    IssueHistoryID      INT             NOT NULL,               -- journal_details.id
    JournalID           INT             NOT NULL,
    IssueID             INT             NOT NULL,               -- degenerada
    UserKey             INT             NOT NULL,
    ChangeDateKey       INT             NOT NULL,
    ChangeTimestamp     DATETIME2(0)    NOT NULL,
    ChangeProperty      NVARCHAR(30)   NOT NULL,               -- status_id / done_ratio / fixed_version_id
    OldStatusKey        INT             NOT NULL,               -- -1 SK si no aplica
    NewStatusKey        INT             NOT NULL,
    OldDoneRatio        INT             NULL,
    NewDoneRatio        INT             NULL,
    OldVersionKey       INT             NOT NULL,
    NewVersionKey       INT             NOT NULL,
    IsClosingEvent      BIT             NOT NULL CONSTRAINT DF_FactIssueHistory_IsClosing DEFAULT (0),
    CONSTRAINT PK_FactIssueHistory PRIMARY KEY CLUSTERED (IssueHistoryID),
    CONSTRAINT FK_FactIssueHistory_User      FOREIGN KEY (UserKey)       REFERENCES dbo.DimUser (UserKey),
    CONSTRAINT FK_FactIssueHistory_Date      FOREIGN KEY (ChangeDateKey) REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactIssueHistory_OldStatus FOREIGN KEY (OldStatusKey)  REFERENCES dbo.DimIssueStatus (StatusKey),
    CONSTRAINT FK_FactIssueHistory_NewStatus FOREIGN KEY (NewStatusKey)  REFERENCES dbo.DimIssueStatus (StatusKey),
    CONSTRAINT FK_FactIssueHistory_OldVer    FOREIGN KEY (OldVersionKey) REFERENCES dbo.DimVersion (VersionKey),
    CONSTRAINT FK_FactIssueHistory_NewVer    FOREIGN KEY (NewVersionKey) REFERENCES dbo.DimVersion (VersionKey)
);
GO

CREATE NONCLUSTERED INDEX IX_FactIssueHistory_Issue ON dbo.FactIssueHistory (IssueID);
CREATE NONCLUSTERED INDEX IX_FactIssueHistory_Date  ON dbo.FactIssueHistory (ChangeDateKey);
GO

------------------------------------------------------------------------------
-- FactBurndownDaily (periodic snapshot)
-- Grano: VersionKey × SnapshotDateKey
------------------------------------------------------------------------------
CREATE TABLE dbo.FactBurndownDaily
(
    VersionKey              INT             NOT NULL,
    SnapshotDateKey         INT             NOT NULL,
    ProjectKey              INT             NOT NULL,
    RemainingHours          DECIMAL(9, 2)   NULL,
    RemainingIssues         INT             NOT NULL CONSTRAINT DF_FactBurndown_RemainingIssues DEFAULT (0),
    CompletedHours          DECIMAL(9, 2)   NOT NULL CONSTRAINT DF_FactBurndown_CompletedHours DEFAULT (0),
    IdealRemainingHours     DECIMAL(9, 2)   NULL,
    TotalEstimatedHours     DECIMAL(9, 2)   NULL,
    CONSTRAINT PK_FactBurndownDaily PRIMARY KEY CLUSTERED (VersionKey, SnapshotDateKey),
    CONSTRAINT FK_FactBurndown_Version  FOREIGN KEY (VersionKey)      REFERENCES dbo.DimVersion (VersionKey),
    CONSTRAINT FK_FactBurndown_Date     FOREIGN KEY (SnapshotDateKey) REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactBurndown_Project  FOREIGN KEY (ProjectKey)      REFERENCES dbo.DimProject (ProjectKey)
);
GO

/*==============================================================================
  5. Parametros (control de cargas SSIS / incremental)
==============================================================================*/
CREATE TABLE dbo.Parametros
(
    ID      INT            NOT NULL IDENTITY(1, 1),
    Nombre  VARCHAR(100)   NOT NULL,
    Valor   VARCHAR(500)   NOT NULL,
    CONSTRAINT PK_Parametros PRIMARY KEY CLUSTERED (ID)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Parametros_Nombre ON dbo.Parametros (Nombre);
GO

INSERT INTO dbo.Parametros (Nombre, Valor)
VALUES (N'UltimaFechaEjecucion', N'1900-01-01');
GO

/*==============================================================================
  6. Miembros desconocidos (SK = -1) para FKs nulas del origen
==============================================================================*/
SET IDENTITY_INSERT dbo.DimProject ON;
INSERT INTO dbo.DimProject
(ProjectKey, ProjectID, Nombre, Identificador, Descripcion, ParentProjectID,
 StatusCode, StatusName, EsPublico, DefaultVersionID, CreatedOn, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, N'Sin proyecto', N'unknown', NULL, NULL, 0, N'Desconocido', 0, NULL, NULL, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimProject OFF;

SET IDENTITY_INSERT dbo.DimUser ON;
INSERT INTO dbo.DimUser
(UserKey, UserID, Login, FirstName, LastName, FullName, Email, UserType,
 EsAdmin, StatusCode, LastLoginOn, CreatedOn, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, N'unknown', N'Sin', N'asignar', N'Sin asignar', NULL, N'Unknown',
 0, 0, NULL, NULL, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimUser OFF;

SET IDENTITY_INSERT dbo.DimIssueStatus ON;
INSERT INTO dbo.DimIssueStatus
(StatusKey, StatusID, Nombre, Descripcion, IsClosed, Posicion, DefaultDoneRatio, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, N'Sin estado', NULL, 0, 0, NULL, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimIssueStatus OFF;

SET IDENTITY_INSERT dbo.DimTracker ON;
INSERT INTO dbo.DimTracker
(TrackerKey, TrackerID, Nombre, Descripcion, IsInRoadmap, Posicion, DefaultStatusID, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, N'Sin tracker', NULL, 0, 0, NULL, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimTracker OFF;

SET IDENTITY_INSERT dbo.DimPriority ON;
INSERT INTO dbo.DimPriority
(PriorityKey, PriorityID, Nombre, Posicion, IsDefault, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, N'Sin prioridad', 0, 0, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimPriority OFF;

SET IDENTITY_INSERT dbo.DimActivity ON;
INSERT INTO dbo.DimActivity
(ActivityKey, ActivityID, Nombre, Posicion, IsDefault, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, N'Sin actividad', 0, 0, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimActivity OFF;

SET IDENTITY_INSERT dbo.DimVersion ON;
INSERT INTO dbo.DimVersion
(VersionKey, VersionID, ProjectID, Nombre, Descripcion, EffectiveDate, Status, IsOpen, Sharing,
 CreatedOn, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, -1, N'Sin version', NULL, NULL, N'unknown', 0, N'none', NULL, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimVersion OFF;

SET IDENTITY_INSERT dbo.DimSeverity ON;
INSERT INTO dbo.DimSeverity
(SeverityKey, SeverityID, CustomFieldID, Nombre, Posicion, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, -1, N'Sin severidad', 0, 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimSeverity OFF;

SET IDENTITY_INSERT dbo.DimSprint ON;
INSERT INTO dbo.DimSprint
(SprintKey, SprintID, ProjectID, Nombre, StartDate, EndDate, Status, Activo, FechaInicio, FechaFin)
VALUES
(-1, -1, -1, N'Sin sprint', NULL, NULL, N'unknown', 1, GETDATE(), NULL);
SET IDENTITY_INSERT dbo.DimSprint OFF;

INSERT INTO dbo.DimDate
(DateKey, Fecha, Anio, Trimestre, Mes, NombreMes, AnioMes, SemanaISO, AnioSemanaISO,
 Dia, DiaSemana, NombreDia, EsFinDeSemana, EsDiaHabil)
VALUES
(-1, NULL, 0, 0, 0, N'Sin fecha', N'0000-00', 0, N'0000-W00', 0, 0, N'Sin fecha', 0, 0);
GO

/*==============================================================================
  7. Población de DimDate (2020-01-01 → hoy + 1 año)
==============================================================================*/
DECLARE @StartDate DATE = '2020-01-01';
DECLARE @EndDate   DATE = DATEADD(YEAR, 1, CAST(GETDATE() AS DATE));
DECLARE @d         DATE = @StartDate;

WHILE @d <= @EndDate
BEGIN
    DECLARE @DateKey INT = YEAR(@d) * 10000 + MONTH(@d) * 100 + DAY(@d);
    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @d) + @@DATEFIRST - 2) % 7) + 1; -- 1=lunes
    DECLARE @IsoWeek TINYINT = DATEPART(ISO_WEEK, @d);
    DECLARE @IsoYear INT = YEAR(@d);

    IF @IsoWeek >= 52 AND MONTH(@d) = 1 SET @IsoYear = YEAR(@d) - 1;
    IF @IsoWeek = 1 AND MONTH(@d) = 12 SET @IsoYear = YEAR(@d) + 1;

    INSERT INTO dbo.DimDate
    (
        DateKey, Fecha, Anio, Trimestre, Mes, NombreMes, AnioMes,
        SemanaISO, AnioSemanaISO, Dia, DiaSemana, NombreDia, EsFinDeSemana, EsDiaHabil
    )
    VALUES
    (
        @DateKey, @d, YEAR(@d), DATEPART(QUARTER, @d), MONTH(@d), DATENAME(MONTH, @d),
        FORMAT(@d, 'yyyy-MM'), @IsoWeek,
        CONCAT(FORMAT(@IsoYear, '0000'), '-W', FORMAT(@IsoWeek, '00')),
        DAY(@d), @Dow, DATENAME(WEEKDAY, @d),
        CASE WHEN @Dow IN (6, 7) THEN 1 ELSE 0 END,
        CASE WHEN @Dow IN (6, 7) THEN 0 ELSE 1 END
    );

    SET @d = DATEADD(DAY, 1, @d);
END
GO

/*==============================================================================
  8. Verificación
==============================================================================*/
SELECT t.name AS Tabla, SUM(p.rows) AS Filas
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE SCHEMA_NAME(t.schema_id) = N'dbo'
  AND (t.name LIKE N'Dim%' OR t.name LIKE N'Fact%' OR t.name = N'Parametros')
GROUP BY t.name
ORDER BY t.name;
GO

PRINT N'OK: RedmineDW creado (dims SK/BK+SCD, hechos, Parametros, miembros -1, DimDate).';
GO
