# Retrospectivas — eth-runner

Formato: ¿Qué funcionó bien? · ¿Qué no funcionó? · ¿Qué mejoramos para el próximo sprint?
Calendario de sprints en [03_SPRINT_BACKLOG.md](03_SPRINT_BACKLOG.md). Cada retrospectiva se realiza al cierre de su sprint.

---

## Retrospectiva Sprint 1 — Acceso, arquitectura y contratos (11/09 al 24/09)

**Fecha:** 19/09/2026 · **Asistentes:** Sebastián Carrasco - Lucas Arcos - Luis Orellana

**Funcionó bien**
- Contar con un código base y un stack definido redujo la incertidumbre técnica.
- El acceso formal al repositorio (acuerdo legal firmado el 08/09, invitación el 11/09) dejó claras las reglas de uso del código.

**No funcionó**
- El código base traía supuestos antiguos (PostgreSQL/Supabase y RabbitMQ/Celery) que no encajaban con un runner autónomo.
- El contacto con el equipo del Orquestador llegó recién el 21/09, diez días después de tener acceso al repositorio.

**Mejoras acordadas**
- Simplificar el stack: SQLite por runner y BackgroundTasks de FastAPI en vez de una cola externa.
- Coordinar con el equipo del Orquestador apenas exista un canal de comunicación.

---

## Retrospectiva Sprint 2 — Seguridad, persistencia y ejecución (25/09 al 08/10)

**Fecha:** 02/10/2026 · **Asistentes:** Sebastián Carrasco

**Funcionó bien**
- La reunión del 26/09 con el equipo del Orquestador resolvió dudas y permitió definir los contratos JSON antes de programar (API-first).
- La firma HMAC y el pase JWT quedaron implementados y separan claramente quién puede ordenar y quién solo puede consultar.

**No funcionó**
- Una base de datos versionada por error quedó con un esquema viejo (`BIGINT` en vez de `INTEGER`) y rompió el autoincremento.

**Mejoras acordadas**
- No versionar `data/*.db` (agregado a `.gitignore`) y regenerar la base al cambiar modelos.

---

## Retrospectiva Sprint 3 — Aislamiento, despliegue y pruebas (09/10 al 22/10)

**Fecha:** 12/10/2026 · **Asistentes:** Sebastián Carrasco -

**Funcionó bien**
- El aislamiento con contenedores efímeros y el fallback automático de versión funcionaron en la prueba de punta a punta.
- El stack se instaló y levantó en Parrot OS (12/10) y en Ubuntu (13/10) siguiendo la guía.
- El simulador permitió probar el runner sin el Orquestador: 5/5 escenarios y 8/8 pruebas de seguridad.
- Los avances se presentaron al docente el 13/10 y el 16/10.

**No funcionó**
- El seeder registraba solo 7 de las 14 herramientas construidas.
- Los adaptadores de Trivy y Wapiti no se ejecutaban porque leían parámetros con `argparse` y no en JSON.
- En Ubuntu el puerto 8000 del host cortaba la conexión; el simulador tuvo que ejecutarse dentro del contenedor.
- La conexión con el Orquestador quedó bloqueada por depender del avance de otro equipo.

**Mejoras acordadas**
- Completar el catálogo y alinear todos los adaptadores al mismo formato de entrada.
- Registrar el runner en el Orquestador original de Alloxentric para no depender del otro equipo (gestión iniciada el 19/10).

---

## Retrospectiva Sprint 4 — Documentación e integración con el Orquestador (23/10 al 05/11)

**Fecha:** 03/11/2026 · **Asistentes:** Sebastián Carrasco -

**Funcionó bien**
- Se completó la documentación técnica (`docs/`) y una batería de pruebas locales automatizada (03/11).
- Alloxentric entregó las credenciales frp para conectar el runner al Orquestador original (03/11).

**No funcionó**
- La planilla de evaluación de casa central revisaba un repositorio distinto al del runner, por lo que aparecían como faltantes Docker, pruebas y documentación.
- La carga de trabajo (código, pruebas, despliegue, demostraciones y reuniones) se concentró en un integrante.

**Mejoras acordadas**
- Subir `docs/` y el código del runner al repositorio evaluado.
- Repartir las tareas pendientes del Sprint 5 (hallazgos, pruebas de red, pruebas unitarias) entre los integrantes, con nombre y fecha.
- Terminar el registro en el Orquestador original y levantar el túnel frp.
