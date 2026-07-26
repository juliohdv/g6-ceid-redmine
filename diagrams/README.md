# Diagramas Draw.io — Redmine BI

Archivos editables con [draw.io](https://app.diagrams.net/) o la extensión **Draw.io Integration** de VS Code/Cursor.

| Archivo | Contenido |
|---------|-----------|
| [redmine-business-processes.drawio](redmine-business-processes.drawio) | Procesos de negocio y tablas MySQL |
| [redmine-star-schema.drawio](redmine-star-schema.drawio) | Modelo dimensional para Power BI |
| [redmine-source-er.drawio](redmine-source-er.drawio) | Esquema ER de tablas fuente |

## Cómo abrir

1. **draw.io desktop / web:** File → Open → seleccionar el archivo `.drawio`.
2. **VS Code / Cursor:** instalar extensión "Draw.io Integration" y abrir el archivo directamente.
3. **Exportar:** desde draw.io → File → Export as → PNG, SVG o PDF.

## Leyenda de colores

- **Amarillo:** tabla/hecho central (`issues`, `FactIssue`)
- **Verde:** registros de tiempo / hechos secundarios
- **Azul:** dimensiones y tablas de referencia
- **Morado:** auditoría (`journals`, `journal_details`)
- **Rojo punteado:** extensiones opcionales (Agile, custom fields)
