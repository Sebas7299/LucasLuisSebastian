# Simulador del Orquestador

Esta carpeta emula al **Orquestador central** mientras el real todavía no está
conectado. Firma las peticiones con HMAC-SHA256 igual que en producción, así que
sirve para probar el runner de punta a punta y para validar su seguridad.

Contenido:

```
simulador/
├── simular_orquestador.py   # el simulador (solo usa Python estándar)
├── escenarios/              # "órdenes" JSON que emulan al Orquestador
│   ├── 01_ls_raiz.json
│   ├── 02_ls_etc.json
│   ├── 03_cat_hostname.json
│   ├── 04_cat_numerado.json
│   └── 05_cat_inexistente.json
└── README_SIMULADOR.md
```

Todos los escenarios usan herramientas **inofensivas** (`ls`, `cat`) que actúan
solo dentro de su propio contenedor efímero. No tocan la red ni sistemas de
terceros. Son para validar el flujo del runner, no para escanear nada.

---

## Paso 1: Publicar el puerto del gateway solo en localhost

En modo local el runner no publica puertos. Para que el simulador llegue al
gateway desde tu equipo, crea un override que publique el puerto **solo en
127.0.0.1** (no en toda la red). El archivo `docker-compose.override.yml` ya
está en `.gitignore`, así que no se sube al repo.

Desde la raíz del proyecto (`~/eth-runner`):

```bash
cat > docker-compose.override.yml << 'EOF'
services:
  api_gateway:
    ports:
      - "127.0.0.1:8000:8000"
EOF

sudo docker compose up -d api_gateway
```

Comprueba que responde:

```bash
curl http://127.0.0.1:8000/
```

Deberías ver `{"message":"Dani-ETH funcionando"}`.

---

## Paso 2: Correr los escenarios

El simulador lee el `INTERNAL_API_TOKEN` desde el `.env` del proyecto
automáticamente. Desde la carpeta `simulador/`:

```bash
cd ~/eth-runner/simulador

# Un escenario suelto
python3 simular_orquestador.py escenario escenarios/01_ls_raiz.json

# Todos los escenarios, uno tras otro
python3 simular_orquestador.py escenarios escenarios/
```

Para cada escenario verás la herramienta, los parámetros, el número de tarea, el
estado final (`completado`), el código de salida y un recorte de la salida. Al
final, un resumen tipo `5/5 escenarios OK`.

> El escenario `05_cat_inexistente.json` prueba el **manejo de errores**: el
> contenedor termina bien, pero el adaptador reporta que el archivo no existe.
> Es intencional: valida que un error de la herramienta no rompe el runner.

---

## Paso 3: Pruebas de seguridad del runner

Este modo comprueba que la autenticación del runner **rechaza** lo que debe
rechazar. No ataca nada externo: solo manda peticiones mal formadas al propio
runner y verifica que responde con el error correcto.

```bash
cd ~/eth-runner/simulador
python3 simular_orquestador.py seguridad
```

Comprueba 8 cosas:

| # | Prueba | Esperado |
|---|--------|----------|
| 1 | Petición sin firma | 401 (rechaza) |
| 2 | Firma HMAC inválida | 401 (rechaza) |
| 3 | Timestamp vencido (anti-replay, +5 min) | 401 (rechaza) |
| 4 | Firma válida (control) | 200 (acepta) |
| 5 | Dashboard `/findings` sin pase JWT | 403 (rechaza) |
| 6 | Pase JWT sin expiración (`exp`) | 401 (rechaza) |
| 7 | Pase JWT vencido | 401 (rechaza) |
| 8 | Pase JWT válido (control) | 200 (acepta) |

Esperado: `8/8 comprobaciones de seguridad pasaron.`

---

## Crear tus propios escenarios

Un escenario es un JSON con esta forma:

```json
{
  "nombre": "Texto descriptivo para el reporte",
  "herramienta": "ls",
  "params": { "ruta": "/", "flags": "-la" },
  "espera_estado": "completado"
}
```

- `herramienta`: nombre tal como está en el Registry (`ls`, `cat`, `nmap`, ...).
- `params`: el objeto que recibe el `run.py` de esa herramienta.
- `espera_estado`: `completado` o `fallido`; sirve para marcar si el resultado
  fue el esperado.

> ⚠️ Para herramientas que tocan la red (nmap, nuclei, etc.) usa **solo**
> objetivos propios o de laboratorio con autorización. Mantén esos escenarios
> fuera de esta carpeta de ejemplos inofensivos, o en una subcarpeta aparte, para
> no correrlos por accidente con `escenarios/`.

---

## Opciones del simulador

```
--url URL         URL base del gateway (default: http://127.0.0.1:8000)
--env-file RUTA   .env de donde leer el token (default: ../.env)
--token TOKEN     Token directo (tiene prioridad sobre --env-file)
```

---

## Alternativa sin publicar puertos

Si prefieres no exponer el puerto, puedes correr el simulador dentro del
contenedor del gateway. Hay que copiar primero el simulador y los escenarios al
contenedor:

```bash
cd ~/eth-runner
sudo docker compose cp simulador runner-api-gateway:/app/simulador
sudo docker compose exec api_gateway python simulador/simular_orquestador.py --url http://localhost:8000 escenarios simulador/escenarios
```
