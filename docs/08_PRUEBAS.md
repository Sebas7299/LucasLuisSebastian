# Plan y resultados de pruebas — eth-runner

## Alcance

| Tipo | Qué valida | Herramienta |
| --- | --- | --- |
| Integración de punta a punta | Orden firmada → contenedor efímero → resultado → persistencia | `simulador/simular_orquestador.py escenarios` |
| Seguridad | Que la autenticación HMAC y JWT rechace lo que debe | `simulador/simular_orquestador.py seguridad` |
| Manejo de errores | Que un fallo de la herramienta no rompa el runner | Escenario `05_cat_inexistente.json` |
| Despliegue | Que el stack se instale y levante en equipos distintos | Guía `INSTALACION_PARROT.md` y `docker compose ps` |
| Persistencia | Que tareas y resultados queden guardados | Consulta a SQLite |

Por ahora, las pruebas de integración usan herramientas inofensivas (`ls`, `cat`) que actúan solo dentro de su contenedor. Así se valida el flujo completo del runner (firma, contenedor efímero, resultado y persistencia) sin riesgo para equipos de terceros.

El equipo está en proceso de preparar entornos controlados y autorizados para probar las herramientas de mayor alcance (Nmap, Nuclei, SQLMap, Nikto, Gobuster, Trivy, Wapiti, entre otras). Estas herramientas solo se ejecutarán contra objetivos propios o con autorización explícita (HU-17).

## Cómo ejecutar

```bash
cd ~/eth-runner
sudo docker compose up -d $(sudo docker compose config --services | grep -v '^frpc$')

cd simulador
python3 simular_orquestador.py escenarios escenarios/
python3 simular_orquestador.py seguridad
```

## Casos de prueba de integración

| ID | Escenario | Entrada | Resultado esperado | Resultado obtenido |
| --- | --- | --- | --- | --- |
| PI-01 | Listar raíz del contenedor | `ls` `{"ruta": "/", "flags": "-la"}` | Estado `completado`, código 0 | OK |
| PI-02 | Listar `/etc` | `ls` `{"ruta": "/etc", "flags": "-la"}` | Estado `completado`, código 0 | OK |
| PI-03 | Leer archivo | `cat` `{"archivo": "/etc/hostname"}` | Estado `completado`, contenido del archivo | OK |
| PI-04 | Leer archivo con flag | `cat` `{"archivo": "/etc/os-release", "flags": "-n"}` | Estado `completado`, líneas numeradas | OK |
| PI-05 | Archivo inexistente | `cat` `{"archivo": "/no/existe/este/archivo.txt"}` | La tarea termina; el adaptador informa `codigo_salida: 1` y el error | OK |
| PI-06 | Directorio inexistente | `ls` `{"ruta": "/no/existe/este/directorio", "flags": "-la"}` | La tarea termina; el adaptador reporta error controlado | Pendiente de corrida en stack |
| PI-07 | Leer `/etc/hosts` | `cat` `{"archivo": "/etc/hosts"}` | Estado `completado`, contenido local | Pendiente de corrida en stack |
| PI-08 | Listar `/tmp` limpio | `ls` `{"ruta": "/tmp", "flags": "-la"}` | Estado `completado`, código 0 | Pendiente de corrida en stack |

**Resultado última corrida ejecutada (PD-01 / PD-02): 5/5 escenarios iniciales correctos.**

## Pruebas unitarias (`tests/`)

Se incorporó una batería inicial de 14 pruebas unitarias con `unittest` (solo librería estándar de Python) para validar localmente la lógica del simulador y de `pruebas_locales.py` sin requerir el stack levantado:

```bash
python -m unittest discover -s tests -v
```

| Módulo de prueba | Qué valida |
| --- | --- |
| `tests/test_simulador_auth.py` | Generación de firma HMAC-SHA256, construcción de JWT HS256 y carga de `INTERNAL_API_TOKEN` |
| `tests/test_simulador_escenarios.py` | Validación de esquema e integridad de todos los JSON en `simulador/escenarios/` |
| `tests/test_simulador_flujo.py` | Omisión de query string en HMAC, flujo de `ejecutar_escenario` y pruebas de seguridad mockeadas |
| `tests/test_pruebas_locales.py` | `Cliente.firmar`, `Cliente.jwt`, `resumen_salida` y ciclo de vida del servidor temporal |

## Casos de prueba de seguridad

| ID | Prueba | Esperado | Obtenido |
| --- | --- | --- | --- |
| PS-01 | Petición sin firma | 401 | 401 |
| PS-02 | Firma HMAC inválida | 401 | 401 |
| PS-03 | Timestamp vencido (anti-replay) | 401 | 401 |
| PS-04 | Firma válida (control) | 200 | 200 |
| PS-05 | Dashboard sin pase JWT | 403 | 403 |
| PS-06 | Pase JWT sin `exp` | 401 | 401 |
| PS-07 | Pase JWT vencido | 401 | 401 |
| PS-08 | Pase JWT válido (control) | 200 | 200 |

**Resultado: 8/8 comprobaciones superadas.**

## Pruebas de despliegue

| ID | Entorno | Resultado |
| --- | --- | --- |
| PD-01 (12/10/2026) | Parrot Security OS (Debian 13, x86_64), Docker 29.9, Compose v5.6 | Stack levantado, 14 herramientas registradas, 5/5 y 8/8 |
| PD-02 (13/10/2026) | Ubuntu (equipo de trabajo) | Stack levantado, 14 herramientas registradas, 5 tareas completadas y persistidas (simulador ejecutado dentro del contenedor del Gateway) |

## Registro de ejecuciones

> **Completar:** captura de cada corrida. Agregar una fila por cada nueva ejecución de `pruebas_locales.py`.

| Fecha | Entorno | Escenarios | Seguridad | Evidencia |
| --- | --- | --- | --- | --- |
| 12/10/2026 | Parrot OS | 5/5 | 8/8 | _captura_ |
| 13/10/2026 | Ubuntu | 5/5 | _completar_ | _captura_ |

## Pendientes

- **Pruebas unitarias de microservicios y cobertura:** la suite de `tests/` cubre el simulador y `pruebas_locales.py`; resta agregar pruebas con `pytest` y medición de cobertura sobre los microservicios internos en el repositorio privado para alcanzar el >80% definido en el DoD.
- **Herramientas de mayor alcance:** en proceso. Se están preparando entornos controlados para probar Nmap, Nuclei, SQLMap, Nikto, Gobuster, Trivy y Wapiti con datos reales.
- **Integración real:** repetir los escenarios con el Orquestador original a través del túnel frp.
