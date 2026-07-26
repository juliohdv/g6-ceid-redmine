# Conexión MySQL para Power BI (localhost)

Parámetros para conectar Power BI Desktop a la base de datos de Redmine.

**Modelo de datos y KPIs:** ver [redmine-bi-model.md](redmine-bi-model.md).

| Parámetro    | Valor        |
|--------------|--------------|
| Servidor     | `127.0.0.1`  |
| Puerto       | `3306`       |
| Base de datos| `redmine_db` |
| Usuario      | `admin`      |
| Contraseña   | `admin`      |

## Power BI Desktop

1. **Obtener datos** → **MySQL database**
2. Servidor: `127.0.0.1:3306`
3. Base de datos: `redmine_db`
4. Modo de conectividad: **Importar** o **DirectQuery** según el volumen de datos

## Notas

- MySQL está expuesto solo en localhost (`127.0.0.1:3306:3306` en `docker-compose.yml`).
- Las credenciales actuales son las de la aplicación Redmine; conviene crear un usuario de solo lectura para BI en una fase posterior.
- Power BI Service (nube) no alcanza `localhost`; requerirá **On-premises data gateway** si se publican informes en la nube.

## Verificación rápida

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 3306
```

```powershell
docker exec redmine_db mysql -u admin -padmin redmine_db -e "SHOW TABLES;"
```
