#!/usr/bin/env bash
# ============================================================================
#  panel_runner.sh  —  Panel de control del eth-runner (Dani-ETH)
# ----------------------------------------------------------------------------
#  Interfaz de consola única para operar el runner en tu máquina:
#    - Levantar / detener el stack (con o sin túnel frp)
#    - Prueba simulada 1   : simulador del Orquestador (escenarios + seguridad)
#    - Prueba completa 1   : laboratorio DVWA         (escaneo real del runner)
#    - Prueba completa 2   : laboratorio OWASP Juice Shop
#    - Estado, logs, reportes y limpieza
#
#  Uso:
#    ./panel_runner.sh            # abre el menú interactivo
#    ./panel_runner.sh simulada1  # ejecuta una acción directa, sin menú
#    ./panel_runner.sh completa1
#    ./panel_runner.sh completa2
#    ./panel_runner.sh up | up-frp | down | estado | logs | limpiar-lab
#
#  SEGURIDAD
#    - El token de frp NO está escrito aquí. Se reutiliza el que ya configuraste
#      (.env + frpc/frpc.toml). Si falta, el panel lo pide oculto (no se muestra
#      ni se guarda en texto plano por este script).
#    - Los laboratorios (DVWA / Juice Shop) son aplicaciones VULNERABLES a
#      propósito. Se publican solo en la interfaz interna de Docker (docker0),
#      nunca en 0.0.0.0, para que no queden expuestos a tu red ni a internet.
#    - Escanea solo objetivos propios o autorizados.
# ============================================================================

set -u

# --- Configuración (ajústala si tu instalación es distinta) ------------------
RUNNER_DIR="${RUNNER_DIR:-$HOME/eth-runner}"   # raíz del repo del runner
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8000}"
SLUG_DEFECTO="${SLUG_DEFECTO:-demo-estudiantes}"
DOMINIO_DEFECTO="${DOMINIO_DEFECTO:-runners.dani27001.com}"   # subDomainHost del frps (para la URL pública)
FRPS_HOST_DEFECTO="${FRPS_HOST_DEFECTO:-20.62.196.39}"        # IP/host de ENTRADA del frps (no la del NAT)
FRP_PUERTO_DEFECTO="${FRP_PUERTO_DEFECTO:-7000}"
ORQ_URL_DEFECTO="${ORQ_URL_DEFECTO:-https://eth-orchestrator.api.dani27001.com}"
PUERTO_DVWA="${PUERTO_DVWA:-4280}"
PUERTO_JUICE="${PUERTO_JUICE:-3000}"
LAB_COMPOSE="${LAB_COMPOSE:-$RUNNER_DIR/laboratorio/docker-compose.lab.yml}"
DIR_RESULTADOS="${DIR_RESULTADOS:-$RUNNER_DIR/resultados}"

# --- Colores ----------------------------------------------------------------
if [[ -t 1 ]]; then
  N="\033[0m"; B="\033[1m"; AZ="\033[36m"; VE="\033[32m"; AM="\033[33m"; RO="\033[31m"
else N=""; B=""; AZ=""; VE=""; AM=""; RO=""; fi
ok(){   printf "${VE}✅ %s${N}\n" "$*"; }
info(){ printf "${AZ}ℹ️  %s${N}\n" "$*"; }
warn(){ printf "${AM}⚠️  %s${N}\n" "$*"; }
err(){  printf "${RO}❌ %s${N}\n" "$*"; }
titulo(){ printf "\n${B}${AZ}=== %s ===${N}\n" "$*"; }

# --- Docker / compose (usa sudo solo si hace falta) -------------------------
if docker info >/dev/null 2>&1; then DK="docker"; else DK="sudo docker"; fi
compose(){ ( cd "$RUNNER_DIR" && $DK compose "$@" ); }

verificar_entorno(){
  if [[ ! -d "$RUNNER_DIR" ]]; then
    err "No encuentro el repo del runner en: $RUNNER_DIR"
    echo "   Ajusta la variable RUNNER_DIR al inicio del script, o ejecútalo así:"
    echo "   RUNNER_DIR=/ruta/a/eth-runner ./panel_runner.sh"
    exit 1
  fi
  if [[ ! -f "$RUNNER_DIR/docker-compose.yml" ]]; then
    err "En $RUNNER_DIR no hay docker-compose.yml. ¿Es la carpeta correcta?"
    exit 1
  fi
}

# IP del host vista desde los contenedores (gateway de la red bridge).
ip_docker0(){
  local ip
  ip="$(ip -4 addr show docker0 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1)"
  [[ -z "$ip" ]] && ip="172.17.0.1"
  printf '%s' "$ip"
}

# ----------------------------------------------------------------------------
#  Levantar / detener el stack
# ----------------------------------------------------------------------------
servicios_sin_frpc(){ compose config --services 2>/dev/null | grep -vx 'frpc'; }

levantar_sin_frp(){
  verificar_entorno
  titulo "Levantando el runner SIN túnel frp"
  info "Construyendo e iniciando servicios (puede tardar la primera vez)..."
  # shellcheck disable=SC2046
  if compose up -d --build $(servicios_sin_frpc); then
    ok "Runner arriba. Gateway local: $GATEWAY_URL"
  else
    err "Falló 'docker compose up'. Revisa el output de arriba."
  fi
}

frp_configurado(){
  local toml="$RUNNER_DIR/frpc/frpc.toml" env="$RUNNER_DIR/.env"
  [[ -f "$toml" ]] || return 1
  grep -q 'serverAddr' "$toml" 2>/dev/null && ! grep -q 'IP_PUBLICA_DEL_FRPS' "$toml" 2>/dev/null || return 1
  [[ -f "$env" ]] && grep -q '^INTERNAL_API_TOKEN=.\+' "$env" 2>/dev/null
}

levantar_con_frp(){
  verificar_entorno
  titulo "Levantando el runner CON túnel frp"

  # Si ya está registrado y configurado, se reutiliza (salvo RECONFIG_FRP=1).
  if frp_configurado \
     && grep -qE '^runner_id *= *"[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}"' "$RUNNER_DIR/frpc/frpc.toml" 2>/dev/null \
     && [[ "${RECONFIG_FRP:-0}" != "1" ]]; then
    ok "Ya hay un runner registrado y un frpc.toml listo. Reutilizo lo guardado."
    info "Para registrar de nuevo (con otro código):  RECONFIG_FRP=1 ./panel_runner.sh up-frp"
    if compose up -d --build; then ok "Runner + túnel frp arriba."; estado_frp; else err "Falló 'docker compose up'."; fi
    return
  fi

  warn "Voy a registrar el runner en el Orquestador y configurar el túnel frp."
  echo "   Datos que entrega Alloxentric: código de activación, URL del orquestador,"
  echo "   slug, host/puerto del frps y token frp."
  echo "   Los secretos se piden ocultos y se guardan SOLO en frpc/frpc.toml (gitignoreado)."
  echo "   ⚠️  El código de activación es de UN SOLO USO y el token se entrega una vez."
  echo
  local codigo orq slug host puerto token nombre url_pub
  read -rs -p "Código de activación (oculto): " codigo; echo
  read -r  -p "URL del orquestador [$ORQ_URL_DEFECTO]: " orq; orq="${orq:-$ORQ_URL_DEFECTO}"; orq="${orq%/}"
  read -r  -p "Slug del cliente [$SLUG_DEFECTO]: " slug; slug="${slug:-$SLUG_DEFECTO}"
  read -r  -p "Nombre del runner [$slug]: " nombre; nombre="${nombre:-$slug}"
  read -r  -p "Host del frps [$FRPS_HOST_DEFECTO]: " host; host="${host:-$FRPS_HOST_DEFECTO}"
  read -r  -p "Puerto del frps [$FRP_PUERTO_DEFECTO]: " puerto; puerto="${puerto:-$FRP_PUERTO_DEFECTO}"
  read -rs -p "Token frp (oculto): " token; echo

  if [[ -z "$codigo" || -z "$orq" || -z "$host" || -z "$token" ]]; then
    err "Faltan datos obligatorios (código, URL del orquestador, host o token). Cancelo."
    unset codigo token; return 1
  fi
  url_pub="https://$slug.$DOMINIO_DEFECTO"

  info "Registrando el runner en $orq ..."
  local resp rc
  resp="$(CODIGO="$codigo" NOMBRE="$nombre" URL="$url_pub" python3 - <<'PY' | curl -sS -X POST "$orq/runners/registrar" -H "Content-Type: application/json" --data @- -w '\n%{http_code}'
import json, os
u = os.environ["URL"]
print(json.dumps({"codigo_activacion": os.environ["CODIGO"], "nombre": os.environ["NOMBRE"],
                  "registry_url": u + "/registry", "executor_url": u + "/executor",
                  "gateway_url": u + "/gateway"}))
PY
)"
  unset codigo
  local http="${resp##*$'\n'}" body="${resp%$'\n'*}"
  if [[ "$http" != "200" ]]; then
    err "El registro falló (HTTP $http). Respuesta: $body"
    echo "   403 = código inválido/usado/expirado · 422 = datos mal formados · 429 = demasiados intentos"
    unset token; return 1
  fi
  local runner_id itoken
  runner_id="$(printf '%s' "$body" | python3 -c 'import sys,json;print(json.load(sys.stdin)["runner_id"])')"
  itoken="$(printf '%s' "$body" | python3 -c 'import sys,json;print(json.load(sys.stdin)["internal_token"])')"
  if [[ -z "$runner_id" || -z "$itoken" ]]; then err "Respuesta inesperada del orquestador."; unset token itoken; return 1; fi
  ok "Runner registrado. runner_id: $runner_id"

  mkdir -p "$RUNNER_DIR/frpc"
  local toml="$RUNNER_DIR/frpc/frpc.toml"
  ( umask 077; cat > "$toml" <<TOML
# Generado por panel_runner.sh — NO subir a git (frpc/frpc.toml está gitignoreado).
serverAddr = "$host"
serverPort = $puerto
loginFailExit = false

[auth]
method = "token"
token = "$token"

[metadatas]
runner_id = "$runner_id"
token = "$itoken"

[[proxies]]
name = "gateway"
type = "http"
localIP = "runner-api-gateway"
localPort = 8000
subdomain = "$slug"
locations = ["/gateway"]
[proxies.metadatas]
runner_id = "$runner_id"
token = "$itoken"

[[proxies]]
name = "registry"
type = "http"
localIP = "runner-tool-registry"
localPort = 8003
subdomain = "$slug"
locations = ["/registry"]
[proxies.metadatas]
runner_id = "$runner_id"
token = "$itoken"

[[proxies]]
name = "executor"
type = "http"
localIP = "runner-tool-executor"
localPort = 8004
subdomain = "$slug"
locations = ["/executor"]
[proxies.metadatas]
runner_id = "$runner_id"
token = "$itoken"
TOML
  )
  unset token itoken
  chmod 600 "$toml" 2>/dev/null || true
  ok "frpc.toml escrito (permisos 600). URL pública: $url_pub"

  info "Levantando el stack completo (incluye frpc)..."
  if compose up -d --build; then
    ok "Runner + túnel frp arriba."
    estado_frp
    echo
    echo "   • 'login to server success' + sin 'start error' → conectado 👍"
    echo "   • 'start error: ...credenciales'               → revisa runner_id/token"
    echo "   • 'token in login doesn't match'               → token frp incorrecto/vencido"
  else
    err "Falló 'docker compose up'."
  fi
}

detener(){
  verificar_entorno
  titulo "Deteniendo el runner"
  compose down && ok "Runner detenido." || err "No se pudo detener."
}

estado(){
  verificar_entorno
  titulo "Estado del stack"
  compose ps
}

estado_frp(){
  info "Últimas líneas del log de frpc:"
  compose logs --tail 15 frpc 2>/dev/null || warn "El servicio frpc no tiene logs todavía."
}

logs(){
  verificar_entorno
  local svc="${1:-}"
  if [[ -z "$svc" ]]; then
    read -r -p "¿De qué servicio? (api_gateway / tool_executor / tool_registry / frpc) [api_gateway]: " svc
    svc="${svc:-api_gateway}"
  fi
  titulo "Logs de $svc (Ctrl+C para salir)"
  compose logs -f --tail 50 "$svc"
}

asegurar_runner_arriba(){
  if ! curl -fsS "$GATEWAY_URL/" >/dev/null 2>&1; then
    warn "El gateway no responde en $GATEWAY_URL."
    read -r -p "¿Levanto el runner (sin frp) ahora? [S/n]: " r
    [[ "${r,,}" == "n" ]] && { err "Necesito el runner arriba para las pruebas."; return 1; }
    levantar_sin_frp
    info "Esperando a que el gateway responda..."
    local i
    for i in $(seq 1 30); do curl -fsS "$GATEWAY_URL/" >/dev/null 2>&1 && break; sleep 2; done
  fi
  curl -fsS "$GATEWAY_URL/" >/dev/null 2>&1 || { err "El gateway sigue sin responder."; return 1; }
  ok "Gateway respondiendo en $GATEWAY_URL"
}

# ----------------------------------------------------------------------------
#  Prueba simulada 1 — simulador del Orquestador (del repositorio)
# ----------------------------------------------------------------------------
prueba_simulada_1(){
  verificar_entorno
  asegurar_runner_arriba || return 1
  titulo "Prueba simulada 1 — simulador del Orquestador"
  local sim="$RUNNER_DIR/simulador/simular_orquestador.py"
  if [[ -f "$sim" ]]; then
    info "Escenarios de integración (ls, cat, curl... herramientas inofensivas):"
    ( cd "$RUNNER_DIR/simulador" && python3 simular_orquestador.py escenarios escenarios/ )
    info "Pruebas de seguridad (HMAC y pase JWT):"
    ( cd "$RUNNER_DIR/simulador" && python3 simular_orquestador.py seguridad )
    ok "Prueba simulada 1 finalizada."
  elif [[ -f "$RUNNER_DIR/pruebas/pruebas_locales.py" ]]; then
    warn "No encontré el simulador; uso la batería local en modo rápido."
    ( cd "$RUNNER_DIR" && python3 pruebas/pruebas_locales.py --rapido )
  else
    err "No encuentro ni simulador/ ni pruebas/pruebas_locales.py en $RUNNER_DIR."
  fi
}

# ----------------------------------------------------------------------------
#  Laboratorios de pruebas (DVWA / Juice Shop)
# ----------------------------------------------------------------------------
escribir_compose_lab(){
  local ip; ip="$(ip_docker0)"
  mkdir -p "$(dirname "$LAB_COMPOSE")"
  cat > "$LAB_COMPOSE" <<YAML
# Laboratorio de pruebas del eth-runner — aplicaciones vulnerables a propósito.
# Generado por panel_runner.sh. Publicado SOLO en la interfaz interna de Docker
# (${ip}), para que lo alcancen los contenedores del runner pero NADIE de tu red.
services:
  dvwa:
    image: ghcr.io/digininja/dvwa:latest
    container_name: lab-dvwa
    environment:
      DB_SERVER: dvwa_db
    depends_on: [dvwa_db]
    ports: ["${ip}:${PUERTO_DVWA}:80"]
    restart: unless-stopped
    profiles: ["dvwa"]
  dvwa_db:
    image: mariadb:10
    container_name: lab-dvwa-db
    environment:
      MYSQL_ROOT_PASSWORD: dvwa
      MYSQL_DATABASE: dvwa
      MYSQL_USER: dvwa
      MYSQL_PASSWORD: p@ssw0rd
    volumes: ["lab_dvwa_db:/var/lib/mysql"]
    restart: unless-stopped
    profiles: ["dvwa"]
  juice:
    image: bkimminich/juice-shop:latest
    container_name: lab-juice
    ports: ["${ip}:${PUERTO_JUICE}:3000"]
    restart: unless-stopped
    profiles: ["juice"]
volumes:
  lab_dvwa_db:
YAML
}

lab_up(){   # $1 = perfil (dvwa|juice)
  escribir_compose_lab
  info "Levantando laboratorio '$1'..."
  $DK compose -f "$LAB_COMPOSE" --profile "$1" up -d
}
lab_down_todo(){
  [[ -f "$LAB_COMPOSE" ]] || { warn "No hay laboratorio generado aún."; return 0; }
  titulo "Deteniendo laboratorios"
  $DK compose -f "$LAB_COMPOSE" --profile dvwa --profile juice down && ok "Laboratorios detenidos." || err "No se pudieron detener."
}

esperar_http(){  # $1 = url, $2 = segundos
  local i; for i in $(seq 1 "${2:-60}"); do curl -fsS -o /dev/null "$1" 2>/dev/null && return 0; sleep 2; done; return 1
}

# Lanza el escáner embebido (reutiliza la firma HMAC y los endpoints del runner)
escanear_objetivo(){  # $1 = url objetivo, $2 = etiqueta
  local url="$1" etiqueta="$2" ip; ip="$(ip_docker0)"
  mkdir -p "$DIR_RESULTADOS"
  local py; py="$(mktemp --suffix=.py)"
  cat > "$py" <<'PY'
import base64, datetime as dt, hashlib, hmac, json, os, sys, time, urllib.request, urllib.error, socket

URL_RUNNER = sys.argv[1]; OBJETIVO = sys.argv[2]; IP = sys.argv[3]
ETIQUETA = sys.argv[4]; DIR_OUT = sys.argv[5]; RAPIDO = sys.argv[6] == "1"; REPO = sys.argv[7]
INCLUIR_HYDRA = (len(sys.argv) > 8 and sys.argv[8] == "1")

def cargar_token():
    if os.environ.get("INTERNAL_API_TOKEN", "").strip():
        return os.environ["INTERNAL_API_TOKEN"].strip()
    for ruta in (os.path.join(REPO, ".env"), os.path.expanduser("~/eth-runner/.env")):
        if os.path.isfile(ruta):
            for linea in open(ruta, encoding="utf-8"):
                if linea.strip().startswith("INTERNAL_API_TOKEN="):
                    v = linea.split("=", 1)[1].strip()
                    if v: return v
    sys.exit("No encontre INTERNAL_API_TOKEN (.env). Levanta el runner primero.")

TOKEN = cargar_token()

def firmar(method, path, body=b""):
    ts = str(int(time.time()))
    sig = hmac.new(TOKEN.encode(), f"{method}:{path}:{ts}:".encode() + body, hashlib.sha256).hexdigest()
    return {"X-Signature": sig, "X-Timestamp": ts, "Content-Type": "application/json"}

def pedir(method, path, payload=None, timeout=60):
    body = json.dumps(payload, separators=(",", ":")).encode() if payload is not None else b""
    h = firmar(method, path.split("?", 1)[0], body)
    req = urllib.request.Request(URL_RUNNER.rstrip("/") + path, data=body or None, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        try: return e.code, json.loads(e.read() or b"null")
        except Exception: return e.code, None
    except Exception as e:
        return 0, str(e)

def preparar_sesion():
    st, u = pedir("POST", "/usuarios/", {"external_id": "panel-lab", "nombre": "panel-lab"})
    uid = (u or {}).get("usuario_id", 1) if isinstance(u, dict) else 1
    st, o = pedir("POST", "/objetivos/", {"usuario_id": uid, "url_objetivo": OBJETIVO})
    oid = (o or {}).get("objetivo_id", 1) if isinstance(o, dict) else 1
    st, s = pedir("POST", "/sesiones/", {"objetivo_id": oid})
    return (s or {}).get("sesion_id", 1) if isinstance(s, dict) else 1

def esperar(tid, maxs):
    t0 = time.time(); r = {}
    while time.time() - t0 < maxs:
        st, r = pedir("GET", f"/proxy/tareas/{tid}")
        if isinstance(r, dict) and r.get("estado") in ("completado", "fallido"):
            return r, int(time.time() - t0)
        time.sleep(3)
    return (r if isinstance(r, dict) else {}), int(time.time() - t0)

def correr(sesion, orden, nombre, herr, params, maxs):
    st, t = pedir("POST", "/proxy/ejecutar",
                  {"herramienta": herr, "params": params, "sesion_id": sesion, "orden_ejecucion": orden})
    fila = {"nombre": nombre, "herramienta": herr}
    if st != 200 or not isinstance(t, dict) or "tarea_id" not in t:
        fila.update(veredicto="FALLO", detalle=f"HTTP {st}: {str(t)[:120]}"); return fila
    tarea, seg = esperar(t["tarea_id"], maxs)
    estado = tarea.get("estado", "?"); cod = tarea.get("codigo_salida")
    fila.update(tarea_id=t["tarea_id"], estado=estado, codigo=cod, duracion=tarea.get("duracion_segundos") or seg)
    if estado == "completado" and cod == 0:   fila["veredicto"] = "OK"
    elif estado == "completado":              fila.update(veredicto="REVISAR", detalle=f"codigo {cod}")
    elif estado == "fallido":                 fila.update(veredicto="FALLO", detalle=str(tarea.get("mensaje_error"))[:120])
    else:                                      fila.update(veredicto="TIEMPO", detalle=f"sigue {estado} tras {maxs}s")
    return fila

base = OBJETIVO.rstrip("/") + "/"
puerto_obj = base.split(":")[2].split("/")[0] if base.count(":") >= 2 else "80"
# (nombre, herramienta, params, espera_max, lenta) — las 14 herramientas del catálogo
PRUEBAS = [
    # --- Operan DENTRO del contenedor efímero (no contra el objetivo web) ---
    ("Listar sistema de archivos del contenedor (ls)", "ls", {"ruta": "/", "flags": "-la"}, 90, False),
    ("Leer archivo del contenedor (cat)", "cat", {"archivo": "/etc/os-release", "flags": "-n"}, 90, False),
    ("Consulta de procesos del contenedor (osquery)", "osquery", {}, 150, False),
    ("Análisis de binario de prueba (radare2)", "radare2", {}, 150, False),
    ("Vulnerabilidades y secretos en /app (trivy)", "trivy",
     {"scan_type": "fs", "target": "/app", "scanners": "vuln,secret"}, 900, True),
    # --- Contra el objetivo web del laboratorio ---
    ("Petición HTTP al objetivo (curl)", "curl", {"url": base, "metodo": "GET"}, 90, False),
    ("Escaneo de puertos/servicios (nmap)", "nmap",
     {"objetivo": IP, "tipo_escaneo": "-sV", "velocidad": 4, "puertos": f"80,443,3000,3306,{puerto_obj}"}, 300, False),
    ("Descubrimiento de rutas (gobuster)", "gobuster", {"url": base, "threads": 20}, 300, False),
    ("Revisión de configuración web (nikto)", "nikto", {"url": base}, 900, True),
    ("Plantillas informativas (nuclei)", "nuclei", {"objetivo": base, "severidad": ["info", "low"], "rate_limit": 50}, 900, True),
    ("Escáner web con crawler (wapiti)", "wapiti", {"url": base, "max_scan_time": 90, "depth": 2, "scope": "folder"}, 600, True),
    ("Búsqueda de XSS reflejado (xsstrike)", "xsstrike", {"url": base + "?q=test", "parametro": "q"}, 400, True),
    ("Inyección SQL nivel mínimo (sqlmap)", "sqlmap", {"url": base + "?id=1", "nivel": 1, "riesgo": 1, "time_sec": 5}, 600, True),
]
# Hydra (fuerza bruta de credenciales): solo si se autoriza, porque es la más intrusiva.
# OJO: los parámetros dependen del adaptador de tu runner y del login del laboratorio;
# puede requerir ajuste. Por eso no corre salvo que lo pidas explícitamente.
if INCLUIR_HYDRA:
    PRUEBAS.append(
        ("Fuerza bruta de login (hydra)", "hydra",
         {"objetivo": IP, "puerto": int(puerto_obj) if puerto_obj.isdigit() else 80,
          "servicio": "http-get", "usuario": "admin",
          "passwords": ["password", "admin", "123456", "root", "dvwa"]}, 600, True))

print(f"\n== Escaneo del runner contra {ETIQUETA}: {OBJETIVO} ==")
ses = preparar_sesion()
ICON = {"OK": "[OK]", "REVISAR": "[~]", "FALLO": "[X]", "TIEMPO": "[t]"}
filas = []; orden = 1
for nombre, herr, params, maxs, lenta in PRUEBAS:
    if RAPIDO and lenta:
        continue
    print(f"  -> {nombre} ({herr})...", flush=True)
    f = correr(ses, orden, nombre, herr, params, maxs); orden += 1
    filas.append(f)
    print(f"     {ICON.get(f['veredicto'],'?')} {f['veredicto']}  {f.get('detalle','')}")

ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
base_out = os.path.join(DIR_OUT, f"escaneo_{ETIQUETA}_{ts}")
with open(base_out + ".json", "w", encoding="utf-8") as fh:
    json.dump({"fecha": dt.datetime.now().isoformat(timespec="seconds"), "objetivo": OBJETIVO,
               "etiqueta": ETIQUETA, "resultados": filas}, fh, ensure_ascii=False, indent=2)
with open(base_out + ".md", "w", encoding="utf-8") as fh:
    fh.write(f"# Escaneo del runner — {ETIQUETA}\n\n")
    fh.write(f"- Fecha: {dt.datetime.now().isoformat(timespec='seconds')}\n- Objetivo: {OBJETIVO}\n\n")
    fh.write("| Herramienta | Prueba | Veredicto | Detalle |\n| --- | --- | --- | --- |\n")
    for f in filas:
        fh.write(f"| {f['herramienta']} | {f['nombre']} | {f['veredicto']} | {str(f.get('detalle','')).replace('|','/')[:80]} |\n")
oks = sum(1 for f in filas if f["veredicto"] == "OK")
print(f"\n  Resumen: {oks}/{len(filas)} OK. Reporte: {base_out}.md")
PY
  local rapido="${RAPIDO:-0}" incluir_hydra="${INCLUIR_HYDRA:-0}"
  python3 -I "$py" "$GATEWAY_URL" "$url" "$ip" "$etiqueta" "$DIR_RESULTADOS" "$rapido" "$RUNNER_DIR" "$incluir_hydra"
  rm -f "$py"
}

prueba_completa_1(){
  verificar_entorno
  asegurar_runner_arriba || return 1
  titulo "Prueba completa 1 — laboratorio DVWA"
  lab_up dvwa
  local ip url; ip="$(ip_docker0)"; url="http://${ip}:${PUERTO_DVWA}/"
  info "Esperando a que DVWA responda en $url ..."
  if ! esperar_http "$url" 60; then
    warn "DVWA tarda en arrancar. La primera vez descarga la imagen; reintenta en un minuto."
  fi
  warn "Si es la primera vez, abre $url y pulsa 'Setup / Reset DB' (login admin/password)."
  preguntar_hydra
  escanear_objetivo "$url" "DVWA"
}

prueba_completa_2(){
  verificar_entorno
  asegurar_runner_arriba || return 1
  titulo "Prueba completa 2 — laboratorio OWASP Juice Shop"
  lab_up juice
  local ip url; ip="$(ip_docker0)"; url="http://${ip}:${PUERTO_JUICE}/"
  info "Esperando a que Juice Shop responda en $url ..."
  esperar_http "$url" 90 || warn "Juice Shop tarda en arrancar; reintenta en un minuto si falla."
  preguntar_hydra
  escanear_objetivo "$url" "JuiceShop"
}

# Pregunta si incluir hydra (la más intrusiva). Exporta INCLUIR_HYDRA para el escáner.
preguntar_hydra(){
  if [[ -n "${INCLUIR_HYDRA:-}" ]]; then return; fi
  echo
  warn "Hydra hace fuerza bruta de credenciales. Solo tiene sentido contra el laboratorio (es tuyo)."
  read -r -p "¿Incluir hydra en el escaneo? (así se usan las 14 herramientas) [s/N]: " r
  if [[ "${r,,}" == "s" ]]; then export INCLUIR_HYDRA=1; else export INCLUIR_HYDRA=0; fi
}

ver_reportes(){
  titulo "Reportes de pruebas"
  if [[ -d "$DIR_RESULTADOS" ]] && ls "$DIR_RESULTADOS"/*.md >/dev/null 2>&1; then
    ls -1t "$DIR_RESULTADOS"/*.md | head -10
    echo; info "Ábrelos con: less '<ruta>'"
  else
    warn "Aún no hay reportes en $DIR_RESULTADOS"
  fi
}

# ----------------------------------------------------------------------------
#  Ver la base de datos del runner (lo que consume el Orquestador)
# ----------------------------------------------------------------------------
ver_base_datos(){
  verificar_entorno
  local db="$RUNNER_DIR/data/runner.db"
  titulo "Base de datos del runner — lo que vería el Orquestador"
  if [[ ! -f "$db" ]]; then
    err "No encuentro la base de datos en $db"
    warn "Levanta el runner y ejecuta al menos una prueba para que se cree."
    return 1
  fi
  local tid="${1:-}"
  python3 -I - "$db" "$tid" <<'PY'
import json, sqlite3, sys
db, tid = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
con.row_factory = sqlite3.Row

def tabla(sql, args=()):
    try: return con.execute(sql, args).fetchall()
    except sqlite3.Error as e: print("   (no se pudo leer:", e, ")"); return []

if tid:
    # Detalle de una tarea: el JSON estructurado que se envía al Orquestador
    r = tabla("SELECT t.id, t.nombre_herramienta, t.estado, t.codigo_salida, "
              "t.duracion_segundos, t.mensaje_error, t.input_params, "
              "r.json_output, r.raw_output "
              "FROM tareas_escaneo t LEFT JOIN resultados_tareas r ON r.tarea_id = t.id "
              "WHERE t.id = ?", (tid,))
    if not r:
        print(f"No hay ninguna tarea con id {tid}."); sys.exit(0)
    row = r[0]
    print(f"Tarea #{row['id']}  —  {row['nombre_herramienta']}")
    print(f"  estado: {row['estado']}   codigo_salida: {row['codigo_salida']}   duracion: {row['duracion_segundos']}s")
    if row["mensaje_error"]:
        print(f"  error: {row['mensaje_error']}")
    print("\n--- input_params (lo que pidió el Orquestador) ---")
    try: print(json.dumps(json.loads(row["input_params"] or "null"), indent=2, ensure_ascii=False))
    except Exception: print(row["input_params"])
    print("\n--- json_output (lo que se devuelve al Orquestador) ---")
    jo = row["json_output"]
    if jo is None:
        print("  (sin json_output; puede estar solo en raw_output)")
    else:
        try: print(json.dumps(json.loads(jo) if isinstance(jo, str) else jo, indent=2, ensure_ascii=False))
        except Exception: print(jo)
    sys.exit(0)

# Resumen: últimas tareas, resultados y hallazgos
print("Últimas 15 tareas de escaneo (tabla tareas_escaneo):\n")
print(f"  {'id':>4}  {'herramienta':<12} {'estado':<11} {'cod':>3}  {'dur':>5}  orden")
for t in tabla("SELECT id, nombre_herramienta, estado, codigo_salida, duracion_segundos, orden_ejecucion "
               "FROM tareas_escaneo ORDER BY id DESC LIMIT 15"):
    print(f"  {t['id']:>4}  {str(t['nombre_herramienta'])[:12]:<12} {str(t['estado'])[:11]:<11} "
          f"{str(t['codigo_salida'] if t['codigo_salida'] is not None else '-'):>3}  "
          f"{str(t['duracion_segundos'] if t['duracion_segundos'] is not None else '-'):>5}  {t['orden_ejecucion']}")

for nombre, sql in (("resultados_tareas", "SELECT COUNT(*) c FROM resultados_tareas"),
                    ("hallazgos",         "SELECT COUNT(*) c FROM hallazgos")):
    r = tabla(sql)
    print(f"\n  Total en {nombre}: {r[0]['c'] if r else 0}")

u = tabla("SELECT COUNT(*) c FROM (SELECT DISTINCT cve_id, title, asset, severity FROM hallazgos)")
if u:
    print(f"  Hallazgos únicos (sin repetir): {u[0]['c']}")

h = tabla("SELECT severity, title, asset, cvss FROM hallazgos ORDER BY id DESC LIMIT 10")
if h:
    print("\nÚltimos hallazgos (tabla hallazgos):")
    for x in h:
        print(f"  [{str(x['severity'])[:8]:<8}] {str(x['title'])[:45]:<45} {x['asset']}  CVSS={x['cvss']}")

print("\nPara ver el JSON completo que se enviaría al Orquestador de una tarea:")
print("   ./panel_runner.sh db <id>        (ej: ./panel_runner.sh db 7)")
PY
}

# ----------------------------------------------------------------------------
#  Exportar el JSON que irá al Orquestador
# ----------------------------------------------------------------------------
exportar_json_orquestador(){
  verificar_entorno
  local db="$RUNNER_DIR/data/runner.db" env="$RUNNER_DIR/.env"
  titulo "Exportar JSON para el Orquestador"
  if [[ ! -f "$db" ]]; then
    err "No encuentro la base de datos en $db. Ejecuta primero un escaneo."
    return 1
  fi
  mkdir -p "$DIR_RESULTADOS"
  local sesion="${1:-}"
  python3 -I - "$db" "$env" "$DIR_RESULTADOS" "$sesion" <<'PY'
import datetime as dt, json, os, sqlite3, sys
db, env, dir_out, sesion = sys.argv[1], sys.argv[2], sys.argv[3], (sys.argv[4] if len(sys.argv) > 4 else "")

runner_id = ""
if os.path.isfile(env):
    for linea in open(env, encoding="utf-8"):
        if linea.strip().startswith("RUNNER_ID="):
            runner_id = linea.split("=", 1)[1].strip()

con = sqlite3.connect(f"file:{db}?mode=ro", uri=True); con.row_factory = sqlite3.Row

def norm(v):
    if isinstance(v, str):
        try: return json.loads(v)
        except Exception: return v
    return v

where = "WHERE t.sesion_id = ?" if sesion else ""
args = (sesion,) if sesion else ()
tareas = con.execute(
    "SELECT t.id, t.sesion_id, t.nombre_herramienta, t.estado, t.codigo_salida, "
    "t.duracion_segundos, t.orden_ejecucion, t.input_params, t.mensaje_error, "
    "r.json_output "
    f"FROM tareas_escaneo t LEFT JOIN resultados_tareas r ON r.tarea_id = t.id {where} "
    "ORDER BY t.id", args).fetchall()

if not tareas:
    print("No hay tareas para exportar" + (f" en la sesión {sesion}." if sesion else ".")); sys.exit(0)

salida = []
for t in tareas:
    salida.append({
        "tarea_id": t["id"],
        "sesion_id": t["sesion_id"],
        "herramienta": t["nombre_herramienta"],
        "estado": t["estado"],
        "codigo_salida": t["codigo_salida"],
        "duracion_segundos": t["duracion_segundos"],
        "orden_ejecucion": t["orden_ejecucion"],
        "input_params": norm(t["input_params"]),
        "mensaje_error": t["mensaje_error"],
        "resultado": norm(t["json_output"]),
    })

# Hallazgos: si se filtra por sesión, se unen por la cadena tarea -> resultado -> hallazgo.
if sesion:
    filas_hz = con.execute(
        "SELECT h.cve_id, h.title, h.severity, h.asset, h.cvss, h.status, h.description, h.category "
        "FROM hallazgos h "
        "JOIN resultados_tareas r ON r.id = h.resultado_tarea_id "
        "JOIN tareas_escaneo t ON t.id = r.tarea_id "
        "WHERE t.sesion_id = ? ORDER BY h.id DESC", (sesion,)).fetchall()
else:
    filas_hz = con.execute(
        "SELECT cve_id, title, severity, asset, cvss, status, description, category "
        "FROM hallazgos ORDER BY id DESC").fetchall()

# Deduplicar: muchas herramientas repiten el mismo hallazgo (p. ej. nuclei).
hallazgos = []
vistos = set()
duplicados = 0
for h in filas_hz:
    d = dict(h)
    clave = (d["cve_id"], d["title"], d["asset"], d["severity"])
    if clave in vistos:
        duplicados += 1
        continue
    vistos.add(clave)
    hallazgos.append(d)

orden_sev = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFO": 4}
hallazgos.sort(key=lambda x: orden_sev.get(x.get("severity"), 5))

resumen_sev = {}
for h in hallazgos:
    resumen_sev[h["severity"]] = resumen_sev.get(h["severity"], 0) + 1

doc = {
    "runner_id": runner_id,
    "exportado_en": dt.datetime.now().isoformat(timespec="seconds"),
    "sesion_id": int(sesion) if sesion.isdigit() else None,
    "total_tareas": len(salida),
    "total_hallazgos": len(hallazgos),
    "resumen_severidad": resumen_sev,
    "tareas": salida,
    "hallazgos": hallazgos,
}

ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
suf = f"sesion{sesion}_" if sesion else ""
ruta = os.path.join(dir_out, f"orquestador_{suf}{ts}.json")
with open(ruta, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, ensure_ascii=False, indent=2)

print(f"Exportadas {len(salida)} tareas y {len(hallazgos)} hallazgos únicos "
      f"({duplicados} repetidos omitidos).")
print(f"Severidad: {resumen_sev}")
print(f"Archivo: {ruta}")
print("\nEste es el JSON estructurado que el Orquestador recibe por tarea")
print("(estado, código de salida y 'resultado' = json_output de cada herramienta).")
PY
}

# ----------------------------------------------------------------------------
#  Limpiar datos de prueba (tareas / resultados / hallazgos)
# ----------------------------------------------------------------------------
limpiar_datos(){
  verificar_entorno
  local db="$RUNNER_DIR/data/runner.db"
  titulo "Limpiar datos de prueba de la base de datos"
  if [[ ! -f "$db" ]]; then err "No encuentro $db"; return 1; fi
  warn "Esto BORRA todas las tareas, resultados y hallazgos guardados."
  warn "No toca usuarios, objetivos, sesiones ni el catálogo de herramientas."
  read -r -p "¿Seguro? Escribe 'si' para confirmar: " r
  [[ "${r,,}" == "si" ]] || { info "Cancelado."; return 0; }
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
borrado = {}
for tabla in ("hallazgos", "resultados_tareas", "tareas_escaneo"):
    try:
        cur = con.execute(f"DELETE FROM {tabla}")
        borrado[tabla] = cur.rowcount
    except sqlite3.Error as e:
        print(f"  (no se pudo limpiar {tabla}: {e})")
con.commit()
try: con.execute("VACUUM"); con.commit()
except sqlite3.Error: pass
for t, n in borrado.items():
    print(f"  {t}: {n} filas borradas")
print("Base de datos limpia.")
PY
}

# ----------------------------------------------------------------------------
#  Menú
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
#  Probar el túnel frp (desde internet hacia este runner)
# ----------------------------------------------------------------------------
probar_tunel(){
  verificar_entorno
  titulo "Prueba del túnel frp"
  local toml="$RUNNER_DIR/frpc/frpc.toml"
  if [[ ! -f "$toml" ]]; then err "No hay frpc.toml. Primero usa la opción 3 (levantar con frp)."; return 1; fi
  local slug base
  slug="$(grep -m1 -E '^subdomain *=' "$toml" | sed -E 's/.*"([^"]+)".*/\1/')"
  slug="${slug:-$SLUG_DEFECTO}"
  base="https://$slug.$DOMINIO_DEFECTO"
  info "URL pública: $base"

  echo
  info "1) Cliente frpc (¿conectado y con los proxies activos?)"
  local lg; lg="$(compose logs --tail 60 frpc 2>/dev/null)"
  if grep -q 'login to server success' <<<"$lg"; then ok "Login al frps correcto"; else warn "Sin 'login to server success' reciente en el log de frpc"; fi
  local n; n="$(grep -c 'start proxy success' <<<"$lg")"
  if [[ "$n" -ge 3 ]]; then ok "Proxies activos (gateway, registry, executor)"; else warn "Proxies con 'start proxy success': $n de 3"; fi
  if grep -q 'start error' <<<"$(tail -n 10 <<<"$lg")"; then err "Hay 'start error' reciente: revisa runner_id/token (opción 9 → frpc)"; fi

  echo
  info "2) Certificado HTTPS del dominio"
  local fin
  fin="$(echo | openssl s_client -connect "$slug.$DOMINIO_DEFECTO:443" -servername "$slug.$DOMINIO_DEFECTO" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
  if [[ -n "$fin" ]]; then
    if echo | openssl s_client -connect "$slug.$DOMINIO_DEFECTO:443" -servername "$slug.$DOMINIO_DEFECTO" -verify_return_error >/dev/null 2>&1; then
      ok "Certificado válido (vence: $fin)"
    else
      warn "Certificado NO válido o vencido (notAfter: $fin). Es del lado del servidor del Orquestador."
    fi
  else
    warn "No pude leer el certificado."
  fi

  echo
  info "3) Acceso a cada servicio por la URL pública"
  local r code estricto=1
  for r in gateway registry executor; do
    code="$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "$base/$r/" 2>/dev/null)"
    if [[ "$code" == "000" ]]; then estricto=0; fi
  done
  if [[ "$estricto" == "0" ]]; then
    warn "La verificación TLS falla. Repito SOLO como diagnóstico, sin verificar el certificado (no se envía ninguna credencial)."
  fi
  local flag=""; [[ "$estricto" == "0" ]] && flag="-k"
  for r in gateway registry executor; do
    code="$(curl -sS $flag -o /dev/null -m 10 -w '%{http_code}' "$base/$r/" 2>/dev/null)"
    case "$code" in
      200|401|403) ok "$r → HTTP $code (el túnel llega al runner)" ;;
      000)         err "$r → sin respuesta" ;;
      404|502|503) err "$r → HTTP $code (el túnel no encuentra ese servicio)" ;;
      *)           warn "$r → HTTP $code" ;;
    esac
  done
  [[ "$estricto" == "0" ]] && warn "Con certificado inválido el Orquestador no podrá validar el runner por HTTPS: avisa al creador."
}

menu(){
  while true; do
    printf "\n${B}${AZ}========= Panel de control eth-runner =========${N}\n"
    printf "  Repo: %s\n" "$RUNNER_DIR"
    printf "  Gateway: %s   |  docker0: %s\n" "$GATEWAY_URL" "$(ip_docker0)"
    printf "${B}-----------------------------------------------${N}\n"
    echo "  1) Estado del stack"
    echo "  2) Levantar runner (SIN frp)"
    echo "  3) Levantar runner (CON frp)"
    echo "  4) Detener runner"
    echo "  5) Prueba simulada 1   (simulador del Orquestador)"
    echo "  6) Prueba completa 1   (laboratorio DVWA)"
    echo "  7) Prueba completa 2   (laboratorio Juice Shop)"
    echo "  8) Ver reportes de pruebas (archivos .md/.json del panel)"
    echo "  9) Ver logs de un servicio"
    echo " 10) Detener laboratorios"
    echo " 11) Ver base de datos (lo que vería el Orquestador)"
    echo " 12) Exportar JSON que irá al Orquestador"
    echo " 13) Limpiar datos de prueba (tareas/resultados/hallazgos)"
    echo " 14) Probar túnel frp (acceso público al runner)"
    echo "  0) Salir"
    printf "${B}-----------------------------------------------${N}\n"
    read -r -p "Opción: " op
    case "$op" in
      1) estado ;;
      2) levantar_sin_frp ;;
      3) levantar_con_frp ;;
      4) detener ;;
      5) prueba_simulada_1 ;;
      6) prueba_completa_1 ;;
      7) prueba_completa_2 ;;
      8) ver_reportes ;;
      9) logs ;;
      10) lab_down_todo ;;
      11) read -r -p "¿Id de tarea para ver su JSON? (vacío = resumen): " t; ver_base_datos "$t" ;;
      12) read -r -p "¿Id de sesión a exportar? (vacío = todas las tareas): " s; exportar_json_orquestador "$s" ;;
      13) limpiar_datos ;;
      14) probar_tunel ;;
      0) echo "Hasta luego."; exit 0 ;;
      *) warn "Opción no válida." ;;
    esac
  done
}

# ----------------------------------------------------------------------------
#  Modo directo (sin menú):  ./panel_runner.sh <comando>
# ----------------------------------------------------------------------------
case "${1:-}" in
  "")            menu ;;
  simulada1)     prueba_simulada_1 ;;
  completa1)     prueba_completa_1 ;;
  completa2)     prueba_completa_2 ;;
  up)            levantar_sin_frp ;;
  up-frp)        levantar_con_frp ;;
  down)          detener ;;
  estado|status) estado ;;
  logs)          logs "${2:-}" ;;
  limpiar-lab)   lab_down_todo ;;
  reportes)      ver_reportes ;;
  db|basedatos)  ver_base_datos "${2:-}" ;;
  exportar|export) exportar_json_orquestador "${2:-}" ;;
  limpiar-datos)   limpiar_datos ;;
  tunel|probar-tunel) probar_tunel ;;
  -h|--help|ayuda)
    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//' | head -40 ;;
  *) err "Comando desconocido: $1"; echo "Usa: $0 [simulada1|completa1|completa2|up|up-frp|down|estado|logs|limpiar-lab|limpiar-datos|tunel|reportes|db [id]|exportar [sesion]]"; exit 1 ;;
esac
