# Diagramas UML — eth-runner

Los diagramas están escritos en Mermaid y GitHub los muestra como imagen al abrir este archivo.

## 1. Casos de uso

```mermaid
flowchart LR
    Orq([Orquestador])
    Front([Frontend / Dashboard])
    Admin([Administrador / Instalador])

    subgraph Runner["Sistema: eth-runner"]
        CU1(Ejecutar herramienta)
        CU2(Consultar estado y resultado de tarea)
        CU3(Registrar usuario, objetivo y sesión)
        CU4(Gestionar catálogo de herramientas y versiones)
        CU5(Consultar hallazgos y métricas)
        CU6(Instalar y registrar el runner)
        CU7(Validar firma HMAC)
        CU8(Validar pase JWT)
    end

    Orq --> CU1
    Orq --> CU2
    Orq --> CU3
    Orq --> CU4
    Front --> CU5
    Admin --> CU6
    CU1 -. include .-> CU7
    CU2 -. include .-> CU7
    CU3 -. include .-> CU7
    CU4 -. include .-> CU7
    CU5 -. include .-> CU8
```

## 2. Diagrama de componentes

```mermaid
flowchart TB
    Orq[Orquestador] -->|HTTPS + HMAC| FRPS[frps de Alloxentric]
    Front[Frontend] -->|HTTPS + JWT| FRPS
    FRPS -->|túnel reverso| FRPC[frpc]

    subgraph Host["Equipo del cliente (Docker Compose)"]
        FRPC --> GW[API Gateway :8000]
        GW -->|HMAC interno| EX[Tool Executor :8004]
        GW -->|HMAC interno| REG[Tool Registry :8003]
        EX -->|HMAC interno| REG
        EX -->|API Docker restringida| PROXY[Docker Socket Proxy :2375]
        PROXY --> C[[Contenedor efímero de herramienta]]
        GW --> DB[(SQLite runner.db)]
        REG --> DB
        EX --> DB
        SEED[Seeder] -->|registra catálogo| REG
    end
```

## 3. Diagrama de secuencia: ejecutar una herramienta

```mermaid
sequenceDiagram
    autonumber
    participant O as Orquestador
    participant G as API Gateway
    participant E as Tool Executor
    participant R as Tool Registry
    participant P as Docker Socket Proxy
    participant C as Contenedor efímero
    participant D as SQLite

    O->>G: POST /proxy/ejecutar (JSON + X-Signature + X-Timestamp)
    G->>G: Validar firma HMAC y timestamp (±5 min)
    alt firma inválida
        G-->>O: 401 Unauthorized
    else firma válida
        G->>E: POST /ejecutar/ (firmado)
        E->>D: Crear tarea (estado = pendiente)
        E-->>G: tarea_id, estado pendiente
        G-->>O: 200 { tarea_id, estado: pendiente }
        Note over E: Ejecución en segundo plano
        E->>R: GET versión activa y fallback
        R-->>E: docker_imagen
        E->>D: estado = corriendo
        E->>P: docker run --rm imagen '<params JSON>'
        P->>C: Crear y arrancar contenedor
        C-->>E: Resultado en JSON (stdout)
        P->>C: Eliminar contenedor
        E->>D: Guardar resultado, estado = completado o fallido
    end

    O->>G: GET /proxy/tareas/{id} (firmado)
    G->>E: GET /ejecutar/tareas/{id}
    E->>D: Leer tarea y resultado
    E-->>G: estado, código de salida, JSON
    G-->>O: 200 resultado
```

## 4. Diagrama de estados de una tarea

```mermaid
stateDiagram-v2
    [*] --> pendiente: orden recibida
    pendiente --> corriendo: inicia contenedor
    corriendo --> completado: código de salida 0
    corriendo --> reintento: código ≠ 0 y hay fallback
    reintento --> completado: fallback exitoso
    reintento --> fallido: fallback falla
    corriendo --> fallido: código ≠ 0 sin fallback o timeout
    completado --> [*]
    fallido --> [*]
```

Los estados que se guardan en `tareas_escaneo.estado` son `pendiente`, `corriendo`, `completado` y `fallido`. El `reintento` con la versión de fallback ocurre dentro del Executor y no se guarda como estado propio; queda registrado en `fallback_usado` y `version_fallback_id`.

## 5. Diagrama de clases (modelo de dominio)

```mermaid
classDiagram
    class Usuario {
        +int id
        +str nombre
        +str email
        +str rol
        +str external_id
    }
    class Objetivo {
        +int id
        +int usuario_id
        +str url_objetivo
    }
    class SesionEscaneo {
        +int id
        +int id_usuario
        +str estado
        +datetime inicio
        +datetime fin
    }
    class Herramienta {
        +int id
        +str nombre
        +str categoria
        +dict esquema_input
        +dict esquema_output
        +str version_actual
    }
    class VersionHerramienta {
        +int id
        +int id_herramienta
        +str version
        +str docker_imagen
        +bool activo
        +bool disponible
    }
    class TareaEscaneo {
        +int id
        +int sesion_id
        +str nombre_herramienta
        +str estado
        +dict input_params
        +int codigo_salida
        +int duracion_segundos
        +bool fallback_usado
    }
    class ResultadoTarea {
        +int id
        +int tarea_id
        +str raw_output
        +dict json_output
    }
    class Hallazgo {
        +int id
        +str cve_id
        +str severity
        +float cvss
        +str asset
        +str status
    }

    Usuario "1" --> "*" Objetivo
    Usuario "1" --> "*" SesionEscaneo
    SesionEscaneo "1" --> "*" TareaEscaneo
    Herramienta "1" --> "*" VersionHerramienta
    Herramienta "1" --> "*" TareaEscaneo
    VersionHerramienta "1" --> "*" TareaEscaneo
    TareaEscaneo "1" --> "*" ResultadoTarea
    ResultadoTarea "1" --> "*" Hallazgo
```
