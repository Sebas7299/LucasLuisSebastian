# Requisitos no funcionales — eth-runner

Cada requisito indica cómo se cumple en el sistema y cómo se verifica.

## Seguridad

| ID | Requisito | Cómo se cumple | Verificación |
| --- | --- | --- | --- |
| RNF-01 | Toda petición servidor-a-servidor debe estar autenticada e íntegra. | Firma HMAC-SHA256 sobre `MÉTODO:RUTA:TIMESTAMP:CUERPO` con secreto compartido (`shared/internal_auth.py`). | Petición sin firma o con firma falsa → 401 (pruebas de seguridad 1 y 2). |
| RNF-02 | El sistema debe resistir ataques de repetición (replay). | El `X-Timestamp` debe estar a menos de 5 minutos de la hora del servidor. | Timestamp de hace 10 minutos → 401 (prueba 3). |
| RNF-03 | El acceso del dashboard debe ser de solo lectura y con vencimiento. | Pase JWT HS256 con claim `exp` obligatorio; no da acceso a la ejecución de herramientas. | JWT sin `exp` o vencido → 401; sin token → 403 (pruebas 5 a 7). |
| RNF-04 | Cada ejecución debe estar aislada del equipo anfitrión. | Un contenedor por tarea con `docker run --rm`; los servicios no tocan el socket real, solo el Docker Socket Proxy. | El `ls` del escenario 1 muestra el sistema de archivos del contenedor, no el del host. |
| RNF-05 | Mínimo privilegio sobre la API de Docker. | El proxy solo habilita contenedores, imágenes e info; deshabilita `EXEC`, `BUILD`, `VOLUMES`, `NETWORKS`, `SECRETS`, `SWARM` y otros. El socket se monta en solo lectura. | Revisión de `docker-compose.yml`, servicio `docker_proxy`. |
| RNF-06 | El runner no debe exponer puertos en la red del cliente. | Ningún servicio publica puertos; la entrada es por túnel reverso frp saliente. | `docker compose ps` no muestra puertos publicados en modo producción. |
| RNF-07 | Falla segura (fail-closed) ante configuración incompleta. | Si `INTERNAL_API_TOKEN` está vacío, los servicios no arrancan. | Levantar sin token produce error al iniciar. |
| RNF-08 | Los secretos no deben quedar en el repositorio. | `.env`, `frpc/frpc.toml` y `data/*.db` están en `.gitignore`; se versiona solo `.env.example`. | `git status` no lista esos archivos. |
| RNF-09 | Aislamiento de datos entre clientes. | Cada runner tiene su propia base; consultar una tarea de otro usuario devuelve 404 (no revela que existe). | `GET /ejecutar/tareas/{id}?usuario_id=` con usuario ajeno → 404. |
| RNF-10 | El dashboard solo puede llamarse desde orígenes conocidos. | CORS con lista explícita de orígenes, sin comodín `*`. | Variable `CORS_ALLOWED_ORIGINS`. |

## Rendimiento y disponibilidad

| ID | Requisito | Cómo se cumple | Verificación |
| --- | --- | --- | --- |
| RNF-11 | La API debe responder de inmediato aunque la herramienta tarde. | La ejecución corre en segundo plano (BackgroundTasks); el POST devuelve `tarea_id` con estado `pendiente`. | El simulador recibe la respuesta antes de que la tarea termine. |
| RNF-12 | Ninguna ejecución puede bloquear el sistema indefinidamente. | Límite de 900 segundos por contenedor; al superarlo la tarea se marca como fallida. | `executor_service.lanzar_container(timeout=900)`. |
| RNF-13 | Los servicios deben recuperarse solos ante caídas. | `restart: unless-stopped` en los servicios; healthcheck en el Tool Registry. | `docker compose ps` muestra `healthy`. |
| RNF-14 | Tolerancia a fallos de una versión de herramienta. | Si la versión activa falla y hay fallback, se reintenta y la versión fallida se desactiva. | Campo `fallback_usado` en la tarea. |

## Mantenibilidad, portabilidad y trazabilidad

| ID | Requisito | Cómo se cumple | Verificación |
| --- | --- | --- | --- |
| RNF-15 | Agregar una herramienta no debe requerir cambiar los microservicios. | Cada herramienta es una carpeta en `tools/` (Dockerfile + `run.py`) y una entrada en el seeder. | Se agregaron 7 herramientas sin tocar el Gateway ni el Executor. |
| RNF-16 | Contrato uniforme de entrada y salida para las herramientas. | Todas reciben un JSON como argumento y devuelven JSON con `resultado`, `codigo_salida` y `error`. | Corrección de Trivy y Wapiti para cumplirlo. |
| RNF-17 | El sistema debe instalarse en cualquier Linux con Docker. | Todo corre en contenedores con Docker Compose; el host solo necesita Docker, git y curl. | Instalado en Parrot OS (Debian 13) y en Ubuntu. |
| RNF-18 | Cada ejecución debe quedar registrada y auditable. | Se guardan parámetros, inicio, fin, duración, código de salida, error y resultado de cada tarea. | Consulta a `tareas_escaneo` y `resultados_tareas`. |
| RNF-19 | Instalación reproducible y con diagnóstico. | `scripts/instalar_runner.sh` es idempotente y verifica servicios y túnel. | Opción `--solo-diagnostico`. |
