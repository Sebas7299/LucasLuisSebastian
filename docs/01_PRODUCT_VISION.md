# Product Vision — eth-runner (Dani-ETH)

## Declaración de visión

**Para** Alloxentric y los clientes de su plataforma Dani-ETH,
**que** necesitan evaluar la seguridad de sus activos de forma continua y no solo en pentests esporádicos y costosos,
**eth-runner** es el motor de ejecución de la plataforma:
**un backend que recibe órdenes firmadas, ejecuta herramientas de seguridad reales en contenedores aislados y devuelve resultados estructurados.**
**A diferencia de** ejecutar herramientas a mano o con scripts sueltos sobre la máquina del analista,
**nuestro producto** aísla cada ejecución, autentica cada petición y no expone puertos en la red del cliente.

## Problema

- El pentesting tradicional es esporádico, caro y depende de especialistas escasos.
- Entre una prueba y otra quedan ventanas de vulnerabilidad sin detectar.
- Correr herramientas como Nmap, Nuclei o SQLMap sin aislamiento pone en riesgo el equipo que las ejecuta y produce salidas difíciles de procesar automáticamente.

## Usuarios y partes interesadas

| Actor | Qué necesita del Runner |
| --- | --- |
| Orquestador central | Enviar órdenes de ejecución firmadas y consultar el resultado de cada tarea. |
| Frontend / Dashboard | Leer hallazgos y métricas con un permiso de solo lectura (pase JWT). |
| Módulo de IA del Orquestador | Recibir resultados en JSON uniforme para redactar el informe ejecutivo. |
| Alloxentric (mandante) | Un componente seguro, desplegable en la red del cliente y fácil de mantener. |
| Equipo de desarrollo | Agregar herramientas nuevas sin modificar el núcleo del sistema. |

## Objetivos del producto

1. Ejecutar herramientas de seguridad a partir de una orden JSON, sin intervención manual.
2. Aislar cada ejecución en un contenedor efímero que se destruye al terminar.
3. Autenticar toda comunicación servidor-a-servidor (HMAC-SHA256) y el acceso del dashboard (JWT).
4. Persistir tareas y resultados localmente, en una base de datos propia de cada runner.
5. Conectarse al Orquestador por un túnel reverso (frp), sin publicar puertos.

## Alcance del MVP

**Incluido:** API Gateway, Tool Registry y Tool Executor; catálogo de 14 herramientas; ejecución asíncrona con fallback de versión; autenticación HMAC y JWT; persistencia en SQLite; instalación con Docker Compose; simulador del Orquestador para pruebas.

**Fuera del alcance de este equipo:** la interfaz gráfica (equipo Frontend), el formulario de alta de campañas y el agente de IA que analiza los resultados (equipo del Orquestador), y la infraestructura frps/DNS/nginx (administrada por Alloxentric).

## Indicadores de éxito

- El 100% de las peticiones sin firma válida se rechazan (verificado: 8/8 pruebas de seguridad).
- Una orden completa el flujo orden → contenedor → resultado → persistencia (verificado: 5/5 escenarios).
- Una herramienta nueva se integra agregando su carpeta en `tools/` y su entrada en el seeder, sin tocar los microservicios.
