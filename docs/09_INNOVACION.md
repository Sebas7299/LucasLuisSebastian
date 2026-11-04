# Innovación — eth-runner

eth-runner no es un script que lanza herramientas: es un servicio que permite ejecutar pentesting de forma remota, segura y repetible dentro de la red de un cliente. Estos son sus aportes principales.

## 1. Modelo de "trabajador ciego" (blind worker)

El runner no decide qué escanear ni a quién: solo ejecuta órdenes firmadas del Orquestador. Separar la decisión de la ejecución permite instalar runners en la red de cada cliente sin entregarles lógica de negocio, y controlar todo desde un punto central.

## 2. Ejecución desechable por tarea

Cada herramienta corre en un contenedor nuevo que se destruye al terminar (`docker run --rm`). Ninguna ejecución deja archivos, procesos ni configuración en el equipo, y una tarea no puede contaminar a la siguiente. Los servicios tampoco acceden al socket real de Docker: pasan por un proxy que bloquea operaciones peligrosas como `exec`, `build` o el montaje de volúmenes.

## 3. Conexión sin puertos abiertos

El runner se conecta hacia afuera mediante un túnel reverso (frp). El cliente no necesita abrir puertos en su firewall ni exponer servicios, lo que reduce la superficie de ataque del propio equipo de seguridad.

## 4. Autenticación por petición

Cada orden lleva una firma HMAC calculada sobre el método, la ruta, el cuerpo y la hora. Una orden interceptada no puede modificarse ni reutilizarse después de 5 minutos. El dashboard usa un pase JWT distinto, de corta duración y sin acceso a la ejecución.

## 5. Catálogo autodescriptivo de herramientas

Cada herramienta registra su esquema de entrada y de salida. El Orquestador (y su agente de IA) pueden consultar el catálogo (`/herramientas/para-orquestador`) y construir órdenes válidas sin conocer de antemano cada herramienta.

## 6. Tolerancia a fallos de versiones

Las herramientas se versionan. Si la versión activa falla, el runner reintenta con una versión de respaldo y desactiva la que falló, sin intervención humana.

## 7. Contrato uniforme para agregar herramientas

Todas las herramientas reciben un JSON y devuelven un JSON con la misma forma. Agregar una herramienta nueva consiste en crear su carpeta y registrarla; los microservicios no cambian.

## 8. Pruebas sin depender de otros equipos

El equipo construyó un simulador del Orquestador que firma peticiones igual que el sistema real. Permite validar el flujo completo y la seguridad aunque la integración con el Orquestador aún no esté disponible.
