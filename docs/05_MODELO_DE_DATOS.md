# Modelo de datos — eth-runner

Motor: **SQLite** (`./data/runner.db`), accedido con SQLAlchemy asíncrono (AioSQLite).
Cada runner tiene su propia base: los datos de un cliente nunca salen de su runner.
Las tablas se crean al iniciar el API Gateway y el Tool Registry (`Base.metadata.create_all`).
Fuente: `shared/database/models/`.

## Diagrama entidad-relación

```mermaid
erDiagram
    usuarios ||--o{ objetivos : "posee"
    usuarios ||--o{ sesiones_escaneo : "inicia"
    sesiones_escaneo ||--o{ tareas_escaneo : "agrupa (sin FK)"
    herramientas ||--o{ versiones_herramientas : "tiene"
    herramientas ||--o{ tareas_escaneo : "se ejecuta en"
    versiones_herramientas ||--o{ tareas_escaneo : "versión usada / fallback"
    tareas_escaneo ||--o{ resultados_tareas : "produce"
    resultados_tareas |o--o{ hallazgos : "origina"

    usuarios {
        int id PK
        string nombre
        string email "único, opcional"
        text password_hash
        string rol
        string external_id "único, id del tenant"
        timestamp created_at
    }
    objetivos {
        int id PK
        bigint usuario_id FK
        text url_objetivo
    }
    sesiones_escaneo {
        int id PK
        bigint id_usuario FK
        string estado
        datetime inicio
        datetime fin
        datetime created_at
        text prompt_ia
    }
    herramientas {
        int id PK
        string nombre "único"
        string nombre_UI
        text descripcion
        json casos_usos
        string categoria
        json esquema_input
        json esquema_output
        string version_actual
        numeric estado
        timestamp created_at
        timestamp updated_at
    }
    versiones_herramientas {
        int id PK
        bigint id_herramienta FK
        string version
        string docker_imagen
        boolean activo
        boolean disponible
        text notas_version
        timestamp check_estado
        numeric estado_check
        timestamp created_at
    }
    tareas_escaneo {
        int id PK
        bigint sesion_id
        bigint herramienta
        string nombre_herramienta
        bigint herramienta_id FK
        bigint version_usada_id FK
        boolean fallback_usado
        bigint version_fallback_id FK
        smallint orden_ejecucion
        string estado
        text comando_raw
        json input_params
        text mensaje_error
        timestamp inicio
        timestamp fin
        smallint codigo_salida
        bigint duracion_segundos
        timestamp created_at
    }
    resultados_tareas {
        int id PK
        bigint tarea_id FK
        string nombre_herramienta
        text raw_output
        json json_output
        timestamp created_at
    }
    hallazgos {
        int id PK
        string cve_id
        string title
        string severity
        string asset
        string status
        float cvss
        text description
        string tab
        string category
        string repetitions
        bigint resultado_tarea_id FK
        timestamp created_at
    }
```

## Diccionario de tablas

| Tabla | Propósito | Claves y relaciones |
| --- | --- | --- |
| `usuarios` | Cliente (tenant) del Orquestador representado en el runner. | `external_id` único: alta idempotente desde el Orquestador. |
| `objetivos` | URL o host autorizado para escanear de un usuario. | `usuario_id` → `usuarios.id`. |
| `sesiones_escaneo` | Campaña de escaneo de un usuario; agrupa tareas. | `id_usuario` → `usuarios.id`. No guarda `objetivo_id` (se usa solo para resolver el usuario). |
| `herramientas` | Catálogo de herramientas con sus esquemas de entrada y salida. | `nombre` único. |
| `versiones_herramientas` | Versiones de cada herramienta y la imagen Docker que las ejecuta. | `id_herramienta` → `herramientas.id`. Una versión activa; las fallidas quedan `disponible = false`. |
| `tareas_escaneo` | Cada ejecución de una herramienta: estado, parámetros, tiempos y código de salida. | `herramienta_id`, `version_usada_id`, `version_fallback_id` → tablas de herramientas. `sesion_id` es relación lógica, sin FK. |
| `resultados_tareas` | Salida de la herramienta: texto crudo y JSON estructurado. | `tarea_id` → `tareas_escaneo.id`. |
| `hallazgos` | Vulnerabilidades para el dashboard (CVE, severidad, CVSS, activo, estado). | `resultado_tarea_id` → `resultados_tareas.id` (opcional). |

## Ciclo de vida de una tarea

`pendiente` → `corriendo` → `completado` o `fallido`. Al pasar a `corriendo` se registra `inicio`; al terminar se guardan `fin`, `codigo_salida`, `duracion_segundos` y el resultado en `resultados_tareas`.

## Observaciones

- `tareas_escaneo.sesion_id` no tiene clave foránea declarada; la integridad depende de la aplicación.
- La tabla `hallazgos` existe y la leen `/findings` y `/metrics/*`, pero todavía no se llena automáticamente desde los resultados (historia HU-16 del backlog).
- No hay migraciones: un cambio en un modelo existente requiere regenerar `data/runner.db` en desarrollo.
