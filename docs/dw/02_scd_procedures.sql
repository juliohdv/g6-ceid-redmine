/*
================================================================================
  DW Redmine BI — Procedimientos SCD (SQL Server)
================================================================================
  Patrón: script de cátedra (ActualizarVendedor / ActualizarTerritorioVenta /
          ActualizarPromocion).

  Prerrequisito: ejecutar docs/dw/01_create_dw.sql

  Clasificación SCD por dimensión
  --------------------------------
  DimUser
    SCD1 : Login, FirstName, LastName, FullName, Email, UserType, EsAdmin, LastLoginOn
    SCD2 : StatusCode

  DimProject
    SCD1 : Nombre, Identificador, Descripcion, ParentProjectID, EsPublico, DefaultVersionID
    SCD2 : StatusCode, StatusName

  DimVersion
    SCD1 : Nombre, Descripcion, Sharing, ProjectID
    SCD2 : Status, IsOpen, EffectiveDate

  DimIssueStatus / DimTracker / DimPriority / DimActivity
    SCD1 : todos los atributos de negocio
    SCD2 : no aplica (como DimPromocion del ejemplo)

  Uso típico desde SSIS (OLE DB Command) tras Lookup por BK:
    EXEC dbo.ActualizarUsuario @UserKey=..., @Login=..., ...

  Uso:
    sqlcmd -S localhost -E -i docs/dw/02_scd_procedures.sql
================================================================================
*/

USE RedmineDW;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  Helpers de comparación NULL-safe (evita que NULL <> x falle en silencio)
==============================================================================*/
-- Se usa inline: ISNULL(a,'') <> ISNULL(b,'')  /  ISNULL(a,-1) <> ISNULL(b,-1)
-- No se crean funciones UDF para mantener el script autocontenido como el de cátedra.

/*==============================================================================
  ActualizarUsuario
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.ActualizarUsuario
(
    @UserKey      INT,
    @Login        NVARCHAR(255),
    @FirstName    NVARCHAR(30),
    @LastName     NVARCHAR(255),
    @FullName     NVARCHAR(290),
    @Email        NVARCHAR(255) = NULL,
    @UserType     NVARCHAR(255) = NULL,
    @EsAdmin      BIT,
    @StatusCode   INT,
    @LastLoginOn  DATETIME2(0) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @LoginActual       NVARCHAR(255),
        @FirstNameActual   NVARCHAR(30),
        @LastNameActual    NVARCHAR(255),
        @FullNameActual    NVARCHAR(290),
        @EmailActual       NVARCHAR(255),
        @UserTypeActual    NVARCHAR(255),
        @EsAdminActual     BIT,
        @StatusCodeActual  INT,
        @LastLoginOnActual DATETIME2(0),
        @UserID            INT,
        @CreatedOn         DATETIME2(0);

    SELECT
        @LoginActual       = Login,
        @FirstNameActual   = FirstName,
        @LastNameActual    = LastName,
        @FullNameActual    = FullName,
        @EmailActual       = Email,
        @UserTypeActual    = UserType,
        @EsAdminActual     = EsAdmin,
        @StatusCodeActual  = StatusCode,
        @LastLoginOnActual = LastLoginOn,
        @UserID            = UserID,
        @CreatedOn         = CreatedOn
    FROM dbo.DimUser
    WHERE UserKey = @UserKey
      AND Activo = 1;

    IF @UserID IS NULL
    BEGIN
        RAISERROR(N'ActualizarUsuario: UserKey %d no existe o no está Activo=1.', 16, 1, @UserKey);
        RETURN;
    END

    /*
      Login, nombres, email, tipo, admin, last login → SCD1
      StatusCode → SCD2 (activo/bloqueado importa en el historial)
    */

    -- SCD1
    IF (
           ISNULL(@LoginActual, N'')       <> ISNULL(@Login, N'')
        OR ISNULL(@FirstNameActual, N'')   <> ISNULL(@FirstName, N'')
        OR ISNULL(@LastNameActual, N'')    <> ISNULL(@LastName, N'')
        OR ISNULL(@FullNameActual, N'')    <> ISNULL(@FullName, N'')
        OR ISNULL(@EmailActual, N'')       <> ISNULL(@Email, N'')
        OR ISNULL(@UserTypeActual, N'')    <> ISNULL(@UserType, N'')
        OR @EsAdminActual                  <> @EsAdmin
        OR ISNULL(@LastLoginOnActual, '19000101') <> ISNULL(@LastLoginOn, '19000101')
    )
    BEGIN
        UPDATE dbo.DimUser
        SET Login       = @Login,
            FirstName   = @FirstName,
            LastName    = @LastName,
            FullName    = @FullName,
            Email       = @Email,
            UserType    = @UserType,
            EsAdmin     = @EsAdmin,
            LastLoginOn = @LastLoginOn
        WHERE UserKey = @UserKey
          AND Activo = 1;
    END

    -- SCD2
    IF (@StatusCodeActual <> @StatusCode)
    BEGIN
        UPDATE dbo.DimUser
        SET Activo = 0,
            FechaFin = GETDATE()
        WHERE UserKey = @UserKey
          AND Activo = 1;

        INSERT INTO dbo.DimUser
        (
            UserID, Login, FirstName, LastName, FullName, Email, UserType,
            EsAdmin, StatusCode, LastLoginOn, CreatedOn,
            Activo, FechaInicio, FechaFin
        )
        VALUES
        (
            @UserID, @Login, @FirstName, @LastName, @FullName, @Email, @UserType,
            @EsAdmin, @StatusCode, @LastLoginOn, @CreatedOn,
            1, GETDATE(), NULL
        );
    END
END
GO

/*==============================================================================
  ActualizarProyecto
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.ActualizarProyecto
(
    @ProjectKey         INT,
    @Nombre             NVARCHAR(255),
    @Identificador      NVARCHAR(255) = NULL,
    @Descripcion        NVARCHAR(1000) = NULL,
    @ParentProjectID    INT = NULL,
    @StatusCode         INT,
    @StatusName         NVARCHAR(20),
    @EsPublico          BIT,
    @DefaultVersionID   INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @NombreActual           NVARCHAR(255),
        @IdentificadorActual    NVARCHAR(255),
        @DescripcionActual      NVARCHAR(1000),
        @ParentProjectIDActual  INT,
        @StatusCodeActual       INT,
        @StatusNameActual       NVARCHAR(20),
        @EsPublicoActual        BIT,
        @DefaultVersionIDActual INT,
        @ProjectID              INT,
        @CreatedOn              DATETIME2(0);

    SELECT
        @NombreActual           = Nombre,
        @IdentificadorActual    = Identificador,
        @DescripcionActual      = Descripcion,
        @ParentProjectIDActual  = ParentProjectID,
        @StatusCodeActual       = StatusCode,
        @StatusNameActual       = StatusName,
        @EsPublicoActual        = EsPublico,
        @DefaultVersionIDActual = DefaultVersionID,
        @ProjectID              = ProjectID,
        @CreatedOn              = CreatedOn
    FROM dbo.DimProject
    WHERE ProjectKey = @ProjectKey
      AND Activo = 1;

    IF @ProjectID IS NULL
    BEGIN
        RAISERROR(N'ActualizarProyecto: ProjectKey %d no existe o no está Activo=1.', 16, 1, @ProjectKey);
        RETURN;
    END

    /*
      Nombre, identificador, descripción, padre, público, versión default → SCD1
      StatusCode / StatusName → SCD2 (activo vs archivado/cerrado)
    */

    -- SCD1
    IF (
           ISNULL(@NombreActual, N'')          <> ISNULL(@Nombre, N'')
        OR ISNULL(@IdentificadorActual, N'')   <> ISNULL(@Identificador, N'')
        OR ISNULL(@DescripcionActual, N'')     <> ISNULL(@Descripcion, N'')
        OR ISNULL(@ParentProjectIDActual, -1)  <> ISNULL(@ParentProjectID, -1)
        OR @EsPublicoActual                    <> @EsPublico
        OR ISNULL(@DefaultVersionIDActual, -1) <> ISNULL(@DefaultVersionID, -1)
    )
    BEGIN
        UPDATE dbo.DimProject
        SET Nombre           = @Nombre,
            Identificador    = @Identificador,
            Descripcion      = @Descripcion,
            ParentProjectID  = @ParentProjectID,
            EsPublico        = @EsPublico,
            DefaultVersionID = @DefaultVersionID
        WHERE ProjectKey = @ProjectKey
          AND Activo = 1;
    END

    -- SCD2
    IF (
           @StatusCodeActual <> @StatusCode
        OR ISNULL(@StatusNameActual, N'') <> ISNULL(@StatusName, N'')
    )
    BEGIN
        UPDATE dbo.DimProject
        SET Activo = 0,
            FechaFin = GETDATE()
        WHERE ProjectKey = @ProjectKey
          AND Activo = 1;

        INSERT INTO dbo.DimProject
        (
            ProjectID, Nombre, Identificador, Descripcion, ParentProjectID,
            StatusCode, StatusName, EsPublico, DefaultVersionID, CreatedOn,
            Activo, FechaInicio, FechaFin
        )
        VALUES
        (
            @ProjectID, @Nombre, @Identificador, @Descripcion, @ParentProjectID,
            @StatusCode, @StatusName, @EsPublico, @DefaultVersionID, @CreatedOn,
            1, GETDATE(), NULL
        );
    END
END
GO

/*==============================================================================
  ActualizarVersion
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.ActualizarVersion
(
    @VersionKey     INT,
    @ProjectID      INT,
    @Nombre         NVARCHAR(255),
    @Descripcion    NVARCHAR(255) = NULL,
    @EffectiveDate  DATE = NULL,
    @Status         NVARCHAR(20) = NULL,
    @IsOpen         BIT,
    @Sharing        NVARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @ProjectIDActual     INT,
        @NombreActual        NVARCHAR(255),
        @DescripcionActual   NVARCHAR(255),
        @EffectiveDateActual DATE,
        @StatusActual        NVARCHAR(20),
        @IsOpenActual        BIT,
        @SharingActual       NVARCHAR(20),
        @VersionID           INT,
        @CreatedOn           DATETIME2(0);

    SELECT
        @ProjectIDActual     = ProjectID,
        @NombreActual        = Nombre,
        @DescripcionActual   = Descripcion,
        @EffectiveDateActual = EffectiveDate,
        @StatusActual        = Status,
        @IsOpenActual        = IsOpen,
        @SharingActual       = Sharing,
        @VersionID           = VersionID,
        @CreatedOn           = CreatedOn
    FROM dbo.DimVersion
    WHERE VersionKey = @VersionKey
      AND Activo = 1;

    IF @VersionID IS NULL
    BEGIN
        RAISERROR(N'ActualizarVersion: VersionKey %d no existe o no está Activo=1.', 16, 1, @VersionKey);
        RETURN;
    END

    /*
      Nombre, descripción, sharing, project dueño → SCD1
      Status, IsOpen, EffectiveDate → SCD2 (cierre de sprint / fecha objetivo)
    */

    -- SCD1
    IF (
           @ProjectIDActual                     <> @ProjectID
        OR ISNULL(@NombreActual, N'')           <> ISNULL(@Nombre, N'')
        OR ISNULL(@DescripcionActual, N'')      <> ISNULL(@Descripcion, N'')
        OR ISNULL(@SharingActual, N'')          <> ISNULL(@Sharing, N'')
    )
    BEGIN
        UPDATE dbo.DimVersion
        SET ProjectID   = @ProjectID,
            Nombre      = @Nombre,
            Descripcion = @Descripcion,
            Sharing     = @Sharing
        WHERE VersionKey = @VersionKey
          AND Activo = 1;
    END

    -- SCD2
    IF (
           ISNULL(@StatusActual, N'') <> ISNULL(@Status, N'')
        OR @IsOpenActual <> @IsOpen
        OR ISNULL(@EffectiveDateActual, '19000101') <> ISNULL(@EffectiveDate, '19000101')
    )
    BEGIN
        UPDATE dbo.DimVersion
        SET Activo = 0,
            FechaFin = GETDATE()
        WHERE VersionKey = @VersionKey
          AND Activo = 1;

        INSERT INTO dbo.DimVersion
        (
            VersionID, ProjectID, Nombre, Descripcion, EffectiveDate,
            Status, IsOpen, Sharing, CreatedOn,
            Activo, FechaInicio, FechaFin
        )
        VALUES
        (
            @VersionID, @ProjectID, @Nombre, @Descripcion, @EffectiveDate,
            @Status, @IsOpen, @Sharing, @CreatedOn,
            1, GETDATE(), NULL
        );
    END
END
GO

/*==============================================================================
  Catálogos — solo SCD1 (equivalente a ActualizarPromocion)
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.ActualizarIssueStatus
(
    @StatusKey          INT,
    @Nombre             NVARCHAR(30),
    @Descripcion        NVARCHAR(255) = NULL,
    @IsClosed           BIT,
    @Posicion           INT = NULL,
    @DefaultDoneRatio   INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @NombreActual           NVARCHAR(30),
        @DescripcionActual      NVARCHAR(255),
        @IsClosedActual         BIT,
        @PosicionActual         INT,
        @DefaultDoneRatioActual INT;

    SELECT
        @NombreActual           = Nombre,
        @DescripcionActual      = Descripcion,
        @IsClosedActual         = IsClosed,
        @PosicionActual         = Posicion,
        @DefaultDoneRatioActual = DefaultDoneRatio
    FROM dbo.DimIssueStatus
    WHERE StatusKey = @StatusKey
      AND Activo = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DimIssueStatus WHERE StatusKey = @StatusKey AND Activo = 1)
    BEGIN
        RAISERROR(N'ActualizarIssueStatus: StatusKey %d no existe o no está Activo=1.', 16, 1, @StatusKey);
        RETURN;
    END

    -- SCD1 (todos los atributos)
    IF (
           ISNULL(@NombreActual, N'')           <> ISNULL(@Nombre, N'')
        OR ISNULL(@DescripcionActual, N'')      <> ISNULL(@Descripcion, N'')
        OR @IsClosedActual                      <> @IsClosed
        OR ISNULL(@PosicionActual, -1)          <> ISNULL(@Posicion, -1)
        OR ISNULL(@DefaultDoneRatioActual, -1)  <> ISNULL(@DefaultDoneRatio, -1)
    )
    BEGIN
        UPDATE dbo.DimIssueStatus
        SET Nombre           = @Nombre,
            Descripcion      = @Descripcion,
            IsClosed         = @IsClosed,
            Posicion         = @Posicion,
            DefaultDoneRatio = @DefaultDoneRatio
        WHERE StatusKey = @StatusKey
          AND Activo = 1;
    END
    -- SCD2 no aplica
END
GO

CREATE OR ALTER PROCEDURE dbo.ActualizarTracker
(
    @TrackerKey         INT,
    @Nombre             NVARCHAR(30),
    @Descripcion        NVARCHAR(255) = NULL,
    @IsInRoadmap        BIT,
    @Posicion           INT = NULL,
    @DefaultStatusID    INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @NombreActual          NVARCHAR(30),
        @DescripcionActual     NVARCHAR(255),
        @IsInRoadmapActual     BIT,
        @PosicionActual        INT,
        @DefaultStatusIDActual INT;

    SELECT
        @NombreActual          = Nombre,
        @DescripcionActual     = Descripcion,
        @IsInRoadmapActual     = IsInRoadmap,
        @PosicionActual        = Posicion,
        @DefaultStatusIDActual = DefaultStatusID
    FROM dbo.DimTracker
    WHERE TrackerKey = @TrackerKey
      AND Activo = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DimTracker WHERE TrackerKey = @TrackerKey AND Activo = 1)
    BEGIN
        RAISERROR(N'ActualizarTracker: TrackerKey %d no existe o no está Activo=1.', 16, 1, @TrackerKey);
        RETURN;
    END

    IF (
           ISNULL(@NombreActual, N'')          <> ISNULL(@Nombre, N'')
        OR ISNULL(@DescripcionActual, N'')     <> ISNULL(@Descripcion, N'')
        OR @IsInRoadmapActual                  <> @IsInRoadmap
        OR ISNULL(@PosicionActual, -1)         <> ISNULL(@Posicion, -1)
        OR ISNULL(@DefaultStatusIDActual, -1)  <> ISNULL(@DefaultStatusID, -1)
    )
    BEGIN
        UPDATE dbo.DimTracker
        SET Nombre          = @Nombre,
            Descripcion     = @Descripcion,
            IsInRoadmap     = @IsInRoadmap,
            Posicion        = @Posicion,
            DefaultStatusID = @DefaultStatusID
        WHERE TrackerKey = @TrackerKey
          AND Activo = 1;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.ActualizarPriority
(
    @PriorityKey    INT,
    @Nombre         NVARCHAR(30),
    @Posicion       INT = NULL,
    @IsDefault      BIT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @NombreActual   NVARCHAR(30),
        @PosicionActual INT,
        @IsDefaultActual BIT;

    SELECT
        @NombreActual    = Nombre,
        @PosicionActual  = Posicion,
        @IsDefaultActual = IsDefault
    FROM dbo.DimPriority
    WHERE PriorityKey = @PriorityKey
      AND Activo = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DimPriority WHERE PriorityKey = @PriorityKey AND Activo = 1)
    BEGIN
        RAISERROR(N'ActualizarPriority: PriorityKey %d no existe o no está Activo=1.', 16, 1, @PriorityKey);
        RETURN;
    END

    IF (
           ISNULL(@NombreActual, N'')   <> ISNULL(@Nombre, N'')
        OR ISNULL(@PosicionActual, -1)  <> ISNULL(@Posicion, -1)
        OR @IsDefaultActual             <> @IsDefault
    )
    BEGIN
        UPDATE dbo.DimPriority
        SET Nombre    = @Nombre,
            Posicion  = @Posicion,
            IsDefault = @IsDefault
        WHERE PriorityKey = @PriorityKey
          AND Activo = 1;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.ActualizarActivity
(
    @ActivityKey    INT,
    @Nombre         NVARCHAR(30),
    @Posicion       INT = NULL,
    @IsDefault      BIT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @NombreActual    NVARCHAR(30),
        @PosicionActual  INT,
        @IsDefaultActual BIT;

    SELECT
        @NombreActual    = Nombre,
        @PosicionActual  = Posicion,
        @IsDefaultActual = IsDefault
    FROM dbo.DimActivity
    WHERE ActivityKey = @ActivityKey
      AND Activo = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DimActivity WHERE ActivityKey = @ActivityKey AND Activo = 1)
    BEGIN
        RAISERROR(N'ActualizarActivity: ActivityKey %d no existe o no está Activo=1.', 16, 1, @ActivityKey);
        RETURN;
    END

    IF (
           ISNULL(@NombreActual, N'')  <> ISNULL(@Nombre, N'')
        OR ISNULL(@PosicionActual, -1) <> ISNULL(@Posicion, -1)
        OR @IsDefaultActual            <> @IsDefault
    )
    BEGIN
        UPDATE dbo.DimActivity
        SET Nombre    = @Nombre,
            Posicion  = @Posicion,
            IsDefault = @IsDefault
        WHERE ActivityKey = @ActivityKey
          AND Activo = 1;
    END
END
GO

/*==============================================================================
  ActualizarParametro — utilidad para SSIS al cerrar la carga
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.ActualizarParametro
(
    @Nombre VARCHAR(100),
    @Valor  VARCHAR(500)
)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.Parametros WHERE Nombre = @Nombre)
        UPDATE dbo.Parametros SET Valor = @Valor WHERE Nombre = @Nombre;
    ELSE
        INSERT INTO dbo.Parametros (Nombre, Valor) VALUES (@Nombre, @Valor);
END
GO

PRINT N'OK: procedimientos SCD creados en RedmineDW.';
GO

/*
------------------------------------------------------------------------------
  Ejemplos de prueba (descomentar tras tener datos cargados)

-- SCD1 usuario (cambia nombre, misma StatusCode):
-- EXEC dbo.ActualizarUsuario
--     @UserKey = 1, @Login = N'alice', @FirstName = N'Alice', @LastName = N'Dev',
--     @FullName = N'Alice Dev', @Email = N'alice@example.com', @UserType = N'User',
--     @EsAdmin = 0, @StatusCode = 1, @LastLoginOn = NULL;

-- SCD2 usuario (cambia StatusCode → cierra fila e inserta nueva SK):
-- EXEC dbo.ActualizarUsuario
--     @UserKey = 1, @Login = N'alice', @FirstName = N'Alice', @LastName = N'Dev',
--     @FullName = N'Alice Dev', @Email = N'alice@example.com', @UserType = N'User',
--     @EsAdmin = 0, @StatusCode = 3, @LastLoginOn = NULL;
-- SELECT * FROM dbo.DimUser WHERE UserID = (SELECT UserID FROM dbo.DimUser WHERE UserKey = 1);

-- Cerrar carga:
-- EXEC dbo.ActualizarParametro @Nombre = N'UltimaFechaEjecucion', @Valor = N'2026-08-06';
------------------------------------------------------------------------------
*/
