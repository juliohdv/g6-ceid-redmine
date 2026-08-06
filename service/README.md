# Servicio Redmine (Docker)

Paso a paso para levantar Redmine + MySQL y cargar el proyecto demo. Pensado para Windows + PowerShell.

Tiempo estimado: **10–20 min** la primera vez (descarga de imágenes).

---

## 0. Requisitos

1. **Docker Desktop** instalado y **en ejecución**.
2. Repo clonado localmente.
3. Puertos libres: **3000** (Redmine) y **3306** (MySQL).

Verificar Docker:

```powershell
docker version
docker compose version
```

---

## 1. Ir a la carpeta del servicio

```powershell
cd <ruta-del-repo>\service
```

Ejemplo:

```powershell
cd E:\dev\g6-ceid-redmine\service
```

---

## 2. Levantar los contenedores

```powershell
docker compose up -d
```

La primera vez descarga `mysql:5.7` y `redmine:latest` (puede tardar).

Comprobar estado:

```powershell
docker compose ps
```

Debes ver `redmine_db` y `redmine` con estado **Up**.

Si `redmine` reinicia en loop, espera ~30 s y reinicia:

```powershell
docker restart redmine
```

Logs:

```powershell
docker logs redmine_db --tail 30
docker logs redmine --tail 30
```

---

## 3. Esperar a que MySQL y Redmine respondan

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 3306
Test-NetConnection -ComputerName 127.0.0.1 -Port 3000
```

`TcpTestSucceeded : True` en ambos.

- UI: http://localhost:3000  
- Login por defecto: **`admin` / `admin`** (puede pedir cambiar la contraseña).

---

## 4. Cargar configuración por defecto de Redmine

**Solo la primera vez** (o si la BD está vacía: sin estados, trackers, prioridades).

```powershell
docker exec -e REDMINE_LANG=en redmine bundle exec rake redmine:load_default_data RAILS_ENV=production
```

Salida esperada: `Default configuration data loaded.`

Verificar:

```powershell
docker exec redmine_db mysql -u admin -padmin redmine_db -e "SELECT COUNT(*) AS statuses FROM issue_statuses; SELECT COUNT(*) AS trackers FROM trackers;"
```

Debe haber filas (> 0).

---

## 5. Ejecutar el seeder de demo

```powershell
cd .\seed
.\run-seed.ps1
```

Equivale a:

```powershell
docker cp .\seed_demo.rb redmine:/tmp/seed_demo.rb
docker exec redmine bundle exec rails runner /tmp/seed_demo.rb RAILS_ENV=production
```

Salida esperada (resumen):

```text
OK: demo seed applied
  project:     bi-demo
  versions:    2
  members:     4
  issues:      8
  time_entries:...
```

Si el proyecto `bi-demo` **ya tiene issues**, el script hace `SKIP` y no duplica.

> Si PowerShell bloquea el `.ps1`:
>
> ```powershell
> Set-ExecutionPolicy -Scope Process Bypass
> .\run-seed.ps1
> ```

---

## 6. Validar datos

```powershell
docker exec redmine_db mysql -u admin -padmin redmine_db -e "
SELECT 'projects' t, COUNT(*) n FROM projects
UNION ALL SELECT 'issues', COUNT(*) FROM issues
UNION ALL SELECT 'time_entries', COUNT(*) FROM time_entries
UNION ALL SELECT 'versions', COUNT(*) FROM versions
UNION ALL SELECT 'members', COUNT(*) FROM members;
"
```

Valores típicos tras el seed: 1 proyecto, 8 issues, ~10 time entries, 2 versions, 4 members.

Proyecto en la UI: http://localhost:3000/projects/bi-demo

---

## 7. Datos de conexión (MySQL)

| Parámetro    | Valor         |
|--------------|---------------|
| Host         | `127.0.0.1`   |
| Puerto       | `3306`        |
| Base         | `redmine_db`  |
| Usuario      | `admin`       |
| Contraseña   | `admin`       |
| Root MySQL   | `rootAdmin`   |

Útil para SSIS, Power BI o clientes MySQL. Más detalle: [docs/mysql-powerbi-connection.md](../docs/mysql-powerbi-connection.md).

---

## 8. Detener / reiniciar

```powershell
cd <ruta-del-repo>\service

# Detener (conserva datos en ./mysql_data y ./redmine_data)
docker compose stop

# Volver a levantar
docker compose start
# o
docker compose up -d
```

**Borrar todo y empezar de cero** (elimina la BD local):

```powershell
docker compose down
Remove-Item -Recurse -Force .\mysql_data, .\redmine_data -ErrorAction SilentlyContinue
docker compose up -d
# Luego repetir pasos 4 y 5
```

---

## Problemas frecuentes

| Síntoma | Qué hacer |
|---------|-----------|
| Puerto 3306 u 3000 ocupado | Cerrar el otro MySQL/servicio o cambiar el mapeo en `docker-compose.yml` |
| `redmine` no arranca | `docker restart redmine`; mirar `docker logs redmine` |
| Seed falla / sin trackers | Ejecutar antes el paso 4 (`load_default_data`) |
| `docker: command not found` | Abrir Docker Desktop y reiniciar la terminal |
| Política de ejecución bloquea `.ps1` | `Set-ExecutionPolicy -Scope Process Bypass` |

---

## Resumen rápido (copia-pega)

```powershell
cd <ruta-del-repo>\service
docker compose up -d
docker compose ps

# Esperar ~30–60 s la primera vez, luego:
docker exec -e REDMINE_LANG=en redmine bundle exec rake redmine:load_default_data RAILS_ENV=production

cd .\seed
.\run-seed.ps1
```

Abrir http://localhost:3000 (`admin` / `admin`).

---

## Archivos relacionados

| Archivo | Uso |
|---------|-----|
| `docker-compose.yml` | Servicios Redmine + MySQL |
| `seed/seed_demo.rb` | Seeder del proyecto `bi-demo` |
| `seed/run-seed.ps1` | Ejecuta el seeder dentro del contenedor |
