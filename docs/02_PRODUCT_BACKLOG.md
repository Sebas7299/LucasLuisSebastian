# Product Backlog — eth-runner

Estimación en Story Points (escala Fibonacci). Prioridad: Alta / Media / Baja.
Estado: Hecho / En curso / Pendiente. Sprints de 2 semanas desde el 11/09/2026 (calendario en [03_SPRINT_BACKLOG.md](03_SPRINT_BACKLOG.md)).

| ID | Historia de usuario | Criterios de aceptación | SP | Prioridad | Sprint | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| HU-01 | Como **Orquestador** quiero enviar una orden de ejecución firmada para que el runner ejecute una herramienta sobre un objetivo. | `POST /proxy/ejecutar` responde con `tarea_id` y estado `pendiente`; la tarea se ejecuta en segundo plano. | 8 | Alta | 2 | Hecho |
| HU-02 | Como **Runner** quiero rechazar peticiones sin firma HMAC válida o con timestamp vencido para que nadie más que el Orquestador pueda darme órdenes. | Sin firma, firma inválida o timestamp fuera de ±5 min → HTTP 401. | 5 | Alta | 2 | Hecho |
| HU-03 | Como **Frontend** quiero consultar hallazgos y métricas con un pase JWT de corta duración para mostrar el dashboard sin poder ejecutar herramientas. | `/findings` y `/metrics/*` exigen JWT con `exp`; sin token → 403; vencido o sin `exp` → 401. | 5 | Media | 2 | Hecho |
| HU-04 | Como **administrador** quiero registrar y versionar herramientas en un catálogo para controlar qué imagen se ejecuta. | CRUD de herramientas y versiones en el Tool Registry; una versión activa por herramienta. | 8 | Alta | 2 | Hecho |
| HU-05 | Como **Runner** quiero ejecutar cada herramienta en un contenedor efímero a través del Docker Socket Proxy para no comprometer el equipo anfitrión. | `docker run --rm` por tarea; el proxy no permite exec, build ni volúmenes. | 8 | Alta | 3 | Hecho |
| HU-06 | Como **Orquestador** quiero consultar el estado y el resultado de una tarea para saber cuándo terminó y qué encontró. | `GET /proxy/tareas/{id}` devuelve estado, código de salida, duración y JSON de resultado. | 3 | Alta | 3 | Hecho |
| HU-07 | Como **Runner** quiero persistir tareas y resultados en una base de datos local para conservar el historial de cada ejecución. | Tablas `tareas_escaneo` y `resultados_tareas` en SQLite; los datos sobreviven a reinicios. | 5 | Alta | 2 | Hecho |
| HU-08 | Como **Orquestador** quiero dar de alta usuarios, objetivos y sesiones por cliente para separar los datos de cada tenant. | `POST /usuarios` idempotente por `external_id`; `POST /objetivos` y `POST /sesiones`. | 5 | Media | 2 | Hecho |
| HU-09 | Como **Runner** quiero reintentar con una versión de respaldo si la versión activa falla para no perder la ejecución. | Si el contenedor sale con código ≠ 0 y existe fallback, se reintenta y la versión fallida se marca no disponible. | 5 | Media | 3 | Hecho |
| HU-10 | Como **instalador** quiero registrar el runner y generar su configuración con un solo comando para desplegarlo sin pasos manuales. | `scripts/instalar_runner.sh` registra, completa `.env`, genera `frpc.toml`, levanta el stack y diagnostica. | 5 | Media | 3 | Hecho |
| HU-11 | Como **Runner** quiero exponerme mediante un túnel frp para comunicarme con el Orquestador sin abrir puertos en la red del cliente. | El diagnóstico muestra `start proxy success` para gateway, registry y executor. | 8 | Alta | 4–5 | En curso (depende de credenciales del Orquestador original) |
| HU-12 | Como **equipo** quiero que el catálogo inicial registre las 14 herramientas construidas para que todas puedan ejecutarse. | El seeder registra nmap, sqlmap, nuclei, curl, ls, cat, xsstrike, gobuster, nikto, hydra, radare2, osquery, trivy y wapiti. | 3 | Media | 3 | Hecho |
| HU-13 | Como **equipo** quiero que los adaptadores de Trivy y Wapiti lean sus parámetros en JSON para que el executor pueda invocarlos. | Ambos `run.py` leen `sys.argv[1]` como JSON y devuelven `resultado / codigo_salida / error`. | 2 | Media | 3 | Hecho (prueba real pendiente) |
| HU-14 | Como **equipo** quiero un simulador del Orquestador para probar el runner mientras la integración real no está disponible. | El simulador firma con HMAC, corre escenarios JSON y pruebas de seguridad. | 5 | Alta | 3–4 | Hecho |
| HU-15 | Como **evaluador** quiero documentación técnica del runner para entender cómo instalarlo, operarlo y extenderlo. | README, ARCHITECTURE y carpeta `docs/` con modelo de datos, UML, RNF y pruebas. | 3 | Media | 1–6 | En curso |
| HU-16 | Como **Frontend** quiero que las salidas de las herramientas se conviertan en hallazgos para que el dashboard muestre vulnerabilidades reales. | Al terminar una tarea se crean registros en `hallazgos` con severidad, activo y CVSS. | 8 | Media | 5 | Pendiente |
| HU-17 | Como **equipo** quiero probar las herramientas de mayor alcance en entornos controlados y autorizados para validar sus adaptadores con datos reales. | Nmap, Nuclei, Trivy y Wapiti completan una ejecución contra un objetivo propio. | 5 | Media | 5 | En curso |
| HU-18 | Como **mandante** quiero que se integren nuevas herramientas según las necesidades del proyecto. | Por definir con Alloxentric. | — | Por definir | 6 | Pendiente |

## Resumen

| Estado | Historias | Story Points |
| --- | --- | --- |
| Hecho | 13 | 67 |
| En curso | 3 | 16 |
| Pendiente | 2 | 8 + por definir |
