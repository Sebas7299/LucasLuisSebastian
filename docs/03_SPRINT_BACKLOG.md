# Sprint Backlog — eth-runner

Metodología: Scrum, 6 sprints de 2 semanas, desde el 11 de septiembre de 2026 (día en que el equipo recibió acceso al repositorio del runner).
Las historias (HU-xx) están detalladas en [02_PRODUCT_BACKLOG.md](02_PRODUCT_BACKLOG.md).

| Sprint | Inicio | Término | Foco |
| --- | --- | --- | --- |
| 1 | 11/09/2026 | 24/09/2026 | Acceso, arquitectura y contratos |
| 2 | 25/09/2026 | 08/10/2026 | Seguridad, persistencia y ejecución |
| 3 | 09/10/2026 | 22/10/2026 | Aislamiento, despliegue y pruebas |
| 4 | 23/10/2026 | 05/11/2026 | Documentación e integración con el Orquestador |
| 5 | 06/11/2026 | 19/11/2026 | Integración real y hallazgos |
| 6 | 20/11/2026 | 03/12/2026 | Cierre |

---

## Antes del Sprint 1 — Preparación

| Tarea | HU | Fecha | Estado |
| --- | --- | --- | --- |
| Firma del documento legal para acceder al repositorio del runner | — | 08/09/2026 | Hecho |

## Sprint 1 — Acceso, arquitectura y contratos

**Fechas:** 11/09/2026 al 24/09/2026
**Objetivo:** obtener acceso al proyecto, entender la arquitectura del runner y establecer contacto con el equipo del Orquestador.

| Tarea | HU | Fecha | Estado |
| --- | --- | --- | --- |
| Recepción de la invitación y acceso al repositorio del runner | HU-15 | 11/09/2026 | Hecho |
| Análisis de la arquitectura de microservicios (Gateway, Registry, Executor) | — | __/__/2026 | Hecho |
| Preparar repositorio y estructura base del proyecto | HU-15 | __/__/2026 | Hecho |
| Recepción del contacto del equipo del Orquestador | HU-01 | 21/09/2026 | Hecho |

## Sprint 2 — Seguridad, persistencia y ejecución

**Fechas:** 25/09/2026 al 08/10/2026
**Objetivo:** proteger la comunicación, persistir los datos y ejecutar una orden de punta a punta.

| Tarea | HU | Fecha | Estado |
| --- | --- | --- | --- |
| Primera comunicación con el equipo del Orquestador para resolver dudas | HU-01 | 26/09/2026 | Hecho |
| Acordar esquemas JSON de entrada y salida con el Orquestador | HU-01 | __/__/2026 | Hecho |
| Firma y verificación HMAC-SHA256 con ventana anti-replay | HU-02 | __/__/2026 | Hecho |
| Pase JWT con `exp` obligatorio para el dashboard | HU-03 | __/__/2026 | Hecho |
| Endpoints de usuarios, objetivos y sesiones | HU-08 | __/__/2026 | Hecho |
| Modelo de datos y persistencia en SQLite (SQLAlchemy async) | HU-07 | __/__/2026 | Hecho |
| Tool Registry: CRUD de herramientas y versiones | HU-04 | __/__/2026 | Hecho |
| Endpoint de ejecución en el Gateway y el Executor | HU-01 | __/__/2026 | Hecho |

## Sprint 3 — Aislamiento, despliegue y pruebas

**Fechas:** 09/10/2026 al 22/10/2026
**Objetivo:** ejecutar cada herramienta aislada, dejar el runner instalable y probarlo sin depender del Orquestador.

| Tarea | HU | Fecha | Estado |
| --- | --- | --- | --- |
| Ejecución en contenedores efímeros vía Docker Socket Proxy | HU-05 | __/__/2026 | Hecho |
| Consulta de estado y resultado de tareas | HU-06 | __/__/2026 | Hecho |
| Fallback automático de versión ante fallo | HU-09 | __/__/2026 | Hecho |
| Script de instalación y diagnóstico (`instalar_runner.sh`) | HU-10 | __/__/2026 | Hecho |
| Instalación y prueba en Parrot OS | HU-10 | 12/10/2026 | Hecho |
| Registrar las 14 herramientas en el seeder | HU-12 | 12/10/2026 | Hecho |
| Corregir adaptadores de Trivy y Wapiti | HU-13 | 12/10/2026 | Hecho |
| Simulador del Orquestador y pruebas de seguridad | HU-14 | 12/10/2026 | Hecho |
| Instalación y prueba en Ubuntu | HU-10 | 13/10/2026 | Hecho |
| Presentación de avances al docente | — | 13/10/2026 | Hecho |
| Presentación de avances con el runner en Parrot OS | — | 16/10/2026 | Hecho |
| Gestión con Alloxentric para registrar el runner en el Orquestador original | HU-11 | 19/10/2026 | Hecho |

## Sprint 4 — Documentación e integración con el Orquestador

**Fechas:** 23/10/2026 al 05/11/2026
**Objetivo:** completar la documentación exigida y preparar la conexión con el Orquestador original.

| Tarea | HU | Fecha | Estado |
| --- | --- | --- | --- |
| Documentación técnica (`docs/`) | HU-15 | 03/11/2026 | Hecho |
| Batería de pruebas locales (`pruebas_locales.py`) | HU-14 | 03/11/2026 | Hecho |
| Recepción de credenciales frp para conectar el runner | HU-11 | 03/11/2026 | Hecho |
| Completar fechas en la documentación | HU-15 | 04/11/2026 | Hecho |
| Registro en el Orquestador original y túnel frp | HU-11 | __/__/2026 | En curso |

## Sprint 5 — Integración real y hallazgos

**Fechas:** 06/11/2026 al 19/11/2026
**Objetivo:** operar con el Orquestador real y entregar hallazgos al dashboard.

| Tarea | HU | Fecha | Estado |
| --- | --- | --- | --- |
| Repetir los escenarios con el Orquestador original vía túnel frp | HU-11 | — | Pendiente |
| Conversión de resultados en hallazgos para el dashboard | HU-16 | — | Pendiente |
| Pruebas de herramientas de mayor alcance en entornos controlados | HU-17 | — | En curso |
| Pruebas unitarias con pytest y medición de cobertura | — | — | Pendiente |

## Sprint 6 — Cierre

**Fechas:** 20/11/2026 al 03/12/2026
**Objetivo:** cerrar el proyecto y entregar a Alloxentric.

| Tarea | HU | Fecha | Estado |
| --- | --- | --- | --- |
| Integración de nuevas herramientas según Alloxentric | HU-18 | — | Pendiente |
| Cierre de documentación, informe final y presentación | HU-15 | — | Pendiente |
