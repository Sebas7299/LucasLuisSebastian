#!/usr/bin/env python3
"""Batería de pruebas locales del Runner contra tu propia máquina.

Hace, en orden:
  1. Verifica que el API Gateway responda.
  2. Prueba los endpoints de consulta (catálogo, versiones, tareas).
  3. Corre las 8 pruebas de seguridad (HMAC y pase JWT).
  4. Levanta un servidor web de prueba temporal, escuchando SOLO en la
     interfaz interna de Docker (docker0), para tener un objetivo propio.
  5. Ejecuta las herramientas del catálogo contra tu máquina y contra ese
     servidor de prueba, una por una, esperando su resultado.
  6. Prueba el manejo de errores (herramienta inexistente, parámetro faltante).
  7. Consulta el dashboard (hallazgos y métricas) con un pase JWT.
  8. Guarda un informe en Markdown y en JSON.

Solo usa la librería estándar de Python. Se ejecuta en el host:

  cd ~/eth-runner/simulador
  python3 pruebas_locales.py            # batería completa (15-25 min)
  python3 pruebas_locales.py --rapido   # omite las herramientas lentas (~3 min)
  python3 pruebas_locales.py --solo nmap,gobuster

Requisitos: runner levantado y el gateway publicado en 127.0.0.1:8000
(docker-compose.override.yml). Las herramientas lentas (Nuclei, Trivy)
necesitan internet la primera vez para descargar plantillas y bases de datos.

Uso responsable: todos los objetivos son tu propia máquina o el servidor de
prueba temporal. Hydra queda fuera porque hace fuerza bruta de contraseñas.
"""

import argparse
import base64
import datetime as dt
import hashlib
import hmac
import http.server
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

# --------------------------------------------------------------------------
# Configuración
# --------------------------------------------------------------------------

def cargar_token(env_file: str, token_arg: str) -> str:
    if token_arg:
        return token_arg.strip()
    if os.environ.get("INTERNAL_API_TOKEN", "").strip():
        return os.environ["INTERNAL_API_TOKEN"].strip()
    candidatos = [env_file] if env_file else []
    aqui = os.path.dirname(os.path.abspath(__file__))
    candidatos += [os.path.join(aqui, "..", ".env"), ".env", os.path.expanduser("~/eth-runner/.env")]
    for ruta in candidatos:
        if ruta and os.path.isfile(ruta):
            with open(ruta, encoding="utf-8") as f:
                for linea in f:
                    if linea.strip().startswith("INTERNAL_API_TOKEN="):
                        valor = linea.split("=", 1)[1].strip()
                        if valor:
                            return valor
    sys.exit("❌ No encontré INTERNAL_API_TOKEN (usa --token o --env-file).")


def detectar_ip_docker() -> str:
    """IP del host vista desde los contenedores (gateway de la red bridge)."""
    try:
        salida = subprocess.run(["ip", "-4", "addr", "show", "docker0"],
                                capture_output=True, text=True, timeout=5).stdout
        m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", salida)
        if m:
            return m.group(1)
    except Exception:
        pass
    return "172.17.0.1"


# --------------------------------------------------------------------------
# HTTP + firma (igual que el Orquestador)
# --------------------------------------------------------------------------

class Cliente:
    def __init__(self, base: str, token: str):
        self.base = base.rstrip("/")
        self.token = token

    def firmar(self, method, path, body=b"", ts=None):
        ts = ts if ts is not None else str(int(time.time()))
        msg = f"{method}:{path}:{ts}:".encode() + body
        sig = hmac.new(self.token.encode(), msg, hashlib.sha256).hexdigest()
        return {"X-Signature": sig, "X-Timestamp": ts, "Content-Type": "application/json"}

    def http(self, method, path, headers=None, body=b"", timeout=60):
        req = urllib.request.Request(self.base + path, data=body or None, method=method,
                                     headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                return r.status, _json_o_texto(raw)
        except urllib.error.HTTPError as e:
            return e.code, _json_o_texto(e.read())
        except (urllib.error.URLError, ConnectionError, socket.timeout) as e:
            return 0, str(e)

    def firmado(self, method, path, payload=None):
        body = json.dumps(payload, separators=(",", ":")).encode() if payload is not None else b""
        # El runner firma solo la ruta, sin la query string (?limite=5)
        return self.http(method, path, self.firmar(method, path.split("?", 1)[0], body), body)

    def jwt(self, payload):
        def b64(d):
            return base64.urlsafe_b64encode(d).rstrip(b"=").decode()
        h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
        p = b64(json.dumps(payload, separators=(",", ":")).encode())
        s = hmac.new(self.token.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest()
        return f"{h}.{p}.{b64(s)}"


def _json_o_texto(raw):
    try:
        return json.loads(raw or b"null")
    except Exception:
        return raw.decode(errors="replace") if isinstance(raw, bytes) else raw


# --------------------------------------------------------------------------
# Servidor web de prueba (objetivo propio)
# --------------------------------------------------------------------------

PAGINAS = {
    "index.html": "<html><head><title>Servidor de prueba eth-runner</title></head>"
                  "<body><h1>Servidor de prueba</h1>"
                  "<a href='buscar.html?q=hola'>Buscar</a> <a href='producto.html?id=1'>Producto</a>"
                  "<form action='buscar.html'><input name='q'><button>Buscar</button></form>"
                  "</body></html>",
    "buscar.html": "<html><body><p>Resultados de búsqueda (página estática).</p></body></html>",
    "producto.html": "<html><body><p>Detalle de producto (página estática).</p></body></html>",
    "login.html": "<html><body><form><input name='user'><input type='password' name='pass'></form></body></html>",
    "robots.txt": "User-agent: *\nDisallow: /admin/\nDisallow: /backup/\n",
    "admin/index.html": "<html><body>Panel de administración de prueba</body></html>",
    "backup/index.html": "<html><body>Carpeta de respaldo de prueba</body></html>",
    "images/index.html": "<html><body>Imágenes</body></html>",
    "css/style.css": "body { font-family: sans-serif; }",
    "js/app.js": "console.log('prueba');",
}


class _Silencioso(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


def levantar_servidor_prueba(host, puerto):
    raiz = tempfile.mkdtemp(prefix="eth_runner_objetivo_")
    for ruta, contenido in PAGINAS.items():
        destino = os.path.join(raiz, ruta)
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        with open(destino, "w", encoding="utf-8") as f:
            f.write(contenido)

    def handler(*a, **kw):
        return _Silencioso(*a, directory=raiz, **kw)

    srv = http.server.ThreadingHTTPServer((host, puerto), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


# --------------------------------------------------------------------------
# Escenarios
# --------------------------------------------------------------------------

def escenarios(ip, web, puerto):
    puertos_nmap = f"22,80,443,631,3306,5432,6379,8000,8080,{puerto}"
    # (nombre, herramienta, params, espera_max_seg, lenta)
    return [
        ("Listar raíz del contenedor", "ls", {"ruta": "/", "flags": "-la"}, 90, False),
        ("Leer archivo dentro del contenedor", "cat", {"archivo": "/etc/os-release", "flags": "-n"}, 90, False),
        ("Petición HTTP a la página de prueba", "curl", {"url": web, "metodo": "GET"}, 90, False),
        ("Petición HTTP a robots.txt", "curl", {"url": web + "robots.txt", "metodo": "GET"}, 90, False),
        ("Escaneo de puertos y servicios de tu máquina", "nmap",
         {"objetivo": ip, "tipo_escaneo": "-sV", "velocidad": 4, "puertos": puertos_nmap}, 300, False),
        ("Descubrimiento de rutas en el servidor de prueba", "gobuster", {"url": web, "threads": 20}, 300, False),
        ("Consulta de procesos (osquery, dentro del contenedor)", "osquery", {}, 150, False),
        ("Análisis de binario de prueba (radare2)", "radare2", {}, 150, False),
        ("Revisión de configuración web (nikto)", "nikto", {"url": web}, 900, True),
        ("Plantillas informativas (nuclei)", "nuclei", {"objetivo": web, "severidad": ["info"], "rate_limit": 50}, 900, True),
        ("Escáner web con crawler (wapiti)", "wapiti", {"url": web, "max_scan_time": 60, "depth": 1, "scope": "folder"}, 400, True),
        ("Búsqueda de XSS reflejado (xsstrike)", "xsstrike", {"url": web + "buscar.html?q=hola", "parametro": "q"}, 400, True),
        ("Detección de inyección SQL, nivel mínimo (sqlmap)", "sqlmap",
         {"url": web + "producto.html?id=1", "nivel": 1, "riesgo": 1, "time_sec": 5}, 600, True),
        ("Vulnerabilidades y secretos en /app del contenedor (trivy)", "trivy",
         {"scan_type": "fs", "target": "/app", "scanners": "vuln,secret"}, 900, True),
    ]


def resumen_salida(herramienta, salida):
    """Una línea legible a partir del JSON que devolvió la herramienta."""
    if not isinstance(salida, dict):
        return str(salida)[:120]
    r = salida.get("resultado") if isinstance(salida.get("resultado"), dict) else {}
    try:
        if herramienta == "nmap":
            res = r.get("resumen", {})
            hosts = r.get("hosts", [])
            abiertos = [f"{p['puerto']}/{p.get('servicio', '')}" for h in hosts for p in h.get("puertos_abiertos", [])]
            return f"{res.get('total_puertos_abiertos', len(abiertos))} puertos abiertos: {', '.join(abiertos) or 'ninguno'}"
        if herramienta == "gobuster":
            h = r.get("hallazgos", [])
            return f"{len(h)} rutas: " + ", ".join(f"{x['ruta']}({x['status']})" for x in h[:8])
        if herramienta == "ls":
            return f"{r.get('total', '?')} entradas listadas"
        if herramienta == "cat":
            return f"{r.get('lineas', '?')} líneas leídas"
        if herramienta == "curl":
            primera = (r.get("stdout") or "").splitlines()[:1]
            return primera[0] if primera else "sin respuesta"
        if herramienta == "sqlmap":
            return "vulnerable" if r.get("vulnerable") else "sin inyección detectada"
        if herramienta in ("trivy", "wapiti"):
            return f"estado de la herramienta: {salida.get('status', '?')}"
    except Exception:
        pass
    if salida.get("error"):
        return "error: " + str(salida["error"]).strip()[:110]
    claves = ", ".join(list(r.keys())[:5]) if r else ", ".join(list(salida.keys())[:5])
    return f"salida con: {claves}"


# --------------------------------------------------------------------------
# Ejecución
# --------------------------------------------------------------------------

def esperar_tarea(c, tarea_id, espera_max):
    inicio = time.time()
    r = {}
    while time.time() - inicio < espera_max:
        st, r = c.firmado("GET", f"/proxy/tareas/{tarea_id}")
        if isinstance(r, dict) and r.get("estado") in ("completado", "fallido"):
            return r, int(time.time() - inicio)
        time.sleep(3)
    return (r if isinstance(r, dict) else {}), int(time.time() - inicio)


def correr_herramienta(c, sesion_id, orden, nombre, herramienta, params, espera_max):
    st, t = c.firmado("POST", "/proxy/ejecutar",
                      {"herramienta": herramienta, "params": params, "sesion_id": sesion_id, "orden_ejecucion": orden})
    fila = {"nombre": nombre, "herramienta": herramienta, "params": params}
    if st != 200 or not isinstance(t, dict):
        fila.update(veredicto="FALLO", estado=f"HTTP {st}", codigo=None, duracion=0, detalle=str(t)[:150])
        return fila
    tarea, esperado = esperar_tarea(c, t["tarea_id"], espera_max)
    estado = tarea.get("estado", "?")
    codigo = tarea.get("codigo_salida")
    salida = (tarea.get("resultado") or {}).get("json_output")
    fila.update(tarea_id=t["tarea_id"], estado=estado, codigo=codigo,
                duracion=tarea.get("duracion_segundos") or esperado, salida=salida)
    if estado == "completado" and codigo == 0:
        fila.update(veredicto="OK", detalle=resumen_salida(herramienta, salida))
    elif estado == "completado":
        fila.update(veredicto="REVISAR", detalle=f"terminó con código {codigo}: " + resumen_salida(herramienta, salida))
    elif estado == "fallido":
        fila.update(veredicto="FALLO", detalle=str(tarea.get("mensaje_error"))[:150])
    else:
        fila.update(veredicto="TIEMPO", detalle=f"sigue '{estado}' tras {espera_max}s (puede seguir corriendo)")
    return fila


ICONO = {"OK": "✅", "REVISAR": "⚠️ ", "FALLO": "❌", "TIEMPO": "⏳"}


def main():
    ap = argparse.ArgumentParser(description="Pruebas locales del Runner contra tu propia máquina")
    ap.add_argument("--url", default="http://127.0.0.1:8000")
    ap.add_argument("--env-file", default="")
    ap.add_argument("--token", default="")
    ap.add_argument("--host", default="", help="IP de tu máquina vista desde los contenedores (por defecto docker0)")
    ap.add_argument("--puerto", type=int, default=8088, help="Puerto del servidor web de prueba")
    ap.add_argument("--rapido", action="store_true", help="Omite las herramientas lentas")
    ap.add_argument("--solo", default="", help="Lista de herramientas separadas por coma")
    a = ap.parse_args()

    c = Cliente(a.url, cargar_token(a.env_file, a.token))
    ip = a.host or detectar_ip_docker()
    web = f"http://{ip}:{a.puerto}/"
    informe = {"fecha": dt.datetime.now().isoformat(timespec="seconds"), "gateway": a.url, "objetivo_ip": ip,
               "api": [], "seguridad": [], "herramientas": [], "errores": [], "dashboard": []}

    def chequeo(seccion, nombre, obtenido, esperado):
        ok = obtenido == esperado
        informe[seccion].append({"prueba": nombre, "esperado": esperado, "obtenido": obtenido, "ok": ok})
        print(f"  {'✅' if ok else '❌'} {nombre}: HTTP {obtenido} (esperado {esperado})")
        return ok

    # 1. Salud
    print(f"\n[1] Gateway en {a.url}")
    st, r = c.http("GET", "/")
    if st != 200:
        sys.exit(f"❌ El gateway no responde ({st}: {r}). ¿Está levantado y publicado en 127.0.0.1:8000?")
    print(f"  ✅ {r}")

    # 2. API de consulta
    print("\n[2] Endpoints de consulta (firmados)")
    st, herr = c.firmado("GET", "/proxy/herramientas")
    chequeo("api", "Listar herramientas", st, 200)
    catalogo = [h.get("nombre") for h in herr] if isinstance(herr, list) else []
    print(f"     {len(catalogo)} herramientas: {', '.join(catalogo)}")
    for nombre, ruta in [("Catálogo para el Orquestador", "/proxy/herramientas/para-orquestador"),
                         ("Detalle de nmap", "/proxy/herramientas/nmap"),
                         ("Versiones de nmap", "/proxy/herramientas/nmap/versiones"),
                         ("Últimas tareas", "/proxy/tareas?limite=5")]:
        st, _ = c.firmado("GET", ruta)
        chequeo("api", nombre, st, 200)

    # 3. Seguridad
    print("\n[3] Seguridad de la autenticación")
    p = "/proxy/herramientas"
    chequeo("seguridad", "Petición sin firma", c.http("GET", p)[0], 401)
    chequeo("seguridad", "Firma HMAC inválida",
            c.http("GET", p, {"X-Signature": "0" * 64, "X-Timestamp": str(int(time.time()))})[0], 401)
    chequeo("seguridad", "Timestamp vencido (anti-replay)",
            c.http("GET", p, c.firmar("GET", p, b"", str(int(time.time()) - 600)))[0], 401)
    chequeo("seguridad", "Firma calculada sobre otra ruta",
            c.http("GET", p, c.firmar("GET", "/proxy/tareas", b""))[0], 401)
    chequeo("seguridad", "Firma válida (control)", c.firmado("GET", p)[0], 200)
    chequeo("seguridad", "Dashboard sin pase JWT", c.http("GET", "/findings")[0], 403)
    chequeo("seguridad", "Pase JWT sin exp",
            c.http("GET", "/findings", {"Authorization": "Bearer " + c.jwt({"runner_id": "x"})})[0], 401)
    chequeo("seguridad", "Pase JWT vencido",
            c.http("GET", "/findings", {"Authorization": "Bearer " + c.jwt({"exp": int(time.time()) - 60})})[0], 401)
    chequeo("seguridad", "Pase JWT firmado con otra clave",
            c.http("GET", "/findings", {"Authorization": "Bearer " + Cliente(a.url, "clave-falsa").jwt(
                {"exp": int(time.time()) + 300})})[0], 401)
    chequeo("seguridad", "Pase JWT válido (control)",
            c.http("GET", "/findings", {"Authorization": "Bearer " + c.jwt({"exp": int(time.time()) + 300})})[0], 200)
    chequeo("seguridad", "Ejecutar con pase JWT en vez de HMAC",
            c.http("POST", "/proxy/ejecutar", {"Authorization": "Bearer " + c.jwt({"exp": int(time.time()) + 300}),
                                               "Content-Type": "application/json"}, b"{}")[0], 401)

    # 4. Sesión + servidor de prueba
    print("\n[4] Preparando sesión y objetivo propio")
    st, u = c.firmado("POST", "/usuarios/", {"external_id": "pruebas-locales", "nombre": "Pruebas locales"})
    st2, o = c.firmado("POST", "/objetivos/", {"usuario_id": u["usuario_id"], "url_objetivo": web})
    st3, s = c.firmado("POST", "/sesiones/", {"objetivo_id": o["objetivo_id"]})
    sesion_id = s["sesion_id"]
    print(f"  ✅ usuario {u['usuario_id']}, objetivo {o['objetivo_id']}, sesión {sesion_id}")
    try:
        srv = levantar_servidor_prueba(ip, a.puerto)
    except OSError as e:
        sys.exit(f"❌ No pude levantar el servidor de prueba en {ip}:{a.puerto} ({e}). "
                 "Prueba con --puerto 8099 o --host <tu IP>.")
    print(f"  ✅ servidor de prueba en {web} (solo visible desde Docker en tu máquina)")

    # 5. Herramientas
    lista = escenarios(ip, web, a.puerto)
    if a.solo:
        elegidas = {x.strip() for x in a.solo.split(",") if x.strip()}
        lista = [e for e in lista if e[1] in elegidas]
    elif a.rapido:
        lista = [e for e in lista if not e[4]]
    print(f"\n[5] Ejecutando {len(lista)} herramientas (una a la vez)")
    for i, (nombre, herr, params, espera, _) in enumerate(lista, 1):
        print(f"  … [{i}/{len(lista)}] {herr}: {nombre} (hasta {espera}s)", flush=True)
        fila = correr_herramienta(c, sesion_id, i, nombre, herr, params, espera)
        informe["herramientas"].append(fila)
        print(f"  {ICONO[fila['veredicto']]} {herr} — {fila['detalle']} [{fila['duracion']}s]")

    # 6. Manejo de errores
    print("\n[6] Manejo de errores")
    st, _ = c.firmado("POST", "/proxy/ejecutar",
                      {"herramienta": "no_existe", "params": {}, "sesion_id": sesion_id, "orden_ejecucion": 99})
    ok = st != 200
    informe["errores"].append({"prueba": "Herramienta inexistente", "obtenido": st, "ok": ok})
    print(f"  {'✅' if ok else '❌'} Herramienta inexistente: rechazada con HTTP {st}")
    fila = correr_herramienta(c, sesion_id, 100, "nmap sin el parámetro obligatorio", "nmap", {}, 120)
    ok = fila.get("estado") == "completado" and fila.get("codigo") not in (0, None)
    informe["errores"].append({"prueba": "Parámetro obligatorio faltante", "obtenido": fila.get("codigo"), "ok": ok})
    print(f"  {'✅' if ok else '❌'} Parámetro faltante: la tarea terminó con código {fila.get('codigo')} "
          f"y el runner siguió funcionando")

    # 7. Dashboard
    print("\n[7] Dashboard con pase JWT")
    auth = {"Authorization": "Bearer " + c.jwt({"exp": int(time.time()) + 300})}
    for ruta in ["/findings", "/metrics/risk-score", "/metrics/quick-stats", "/metrics/heatmap", "/metrics/patch-progress"]:
        st, _ = c.http("GET", ruta, auth)
        chequeo("dashboard", ruta, st, 200)

    srv.shutdown()

    # 8. Informe
    def cuenta(lista_, clave="ok"):
        return sum(1 for x in lista_ if x.get(clave)), len(lista_)

    v = [f["veredicto"] for f in informe["herramientas"]]
    resumen = {
        "api": cuenta(informe["api"]), "seguridad": cuenta(informe["seguridad"]),
        "errores": cuenta(informe["errores"]), "dashboard": cuenta(informe["dashboard"]),
        "herramientas": {k: v.count(k) for k in ICONO},
    }
    informe["resumen"] = resumen
    sello = dt.datetime.now().strftime("%Y%m%d_%H%M")
    base = f"resultados_pruebas_{sello}"
    with open(base + ".json", "w", encoding="utf-8") as f:
        json.dump(informe, f, ensure_ascii=False, indent=2, default=str)

    md = [f"# Resultados de pruebas locales — {informe['fecha']}", "",
          f"Gateway: `{a.url}` · Objetivo: tu máquina (`{ip}`) y servidor de prueba `{web}`", "",
          "## Resumen", "",
          "| Bloque | Resultado |", "| --- | --- |",
          f"| Endpoints de consulta | {resumen['api'][0]}/{resumen['api'][1]} |",
          f"| Seguridad | {resumen['seguridad'][0]}/{resumen['seguridad'][1]} |",
          f"| Manejo de errores | {resumen['errores'][0]}/{resumen['errores'][1]} |",
          f"| Dashboard | {resumen['dashboard'][0]}/{resumen['dashboard'][1]} |",
          f"| Herramientas | {resumen['herramientas']['OK']} OK · {resumen['herramientas']['REVISAR']} revisar · "
          f"{resumen['herramientas']['FALLO']} fallo · {resumen['herramientas']['TIEMPO']} tiempo agotado |", "",
          "## Herramientas", "",
          "| # | Herramienta | Prueba | Estado | Código | Duración | Resultado |",
          "| --- | --- | --- | --- | --- | --- | --- |"]
    for i, f_ in enumerate(informe["herramientas"], 1):
        md.append(f"| {i} | {f_['herramienta']} | {f_['nombre']} | {ICONO[f_['veredicto']]} {f_['estado']} | "
                  f"{f_['codigo']} | {f_['duracion']}s | {str(f_['detalle']).replace('|', '/')} |")
    for titulo, clave in [("Seguridad", "seguridad"), ("Endpoints de consulta", "api"), ("Dashboard", "dashboard")]:
        md += ["", f"## {titulo}", "", "| Prueba | Esperado | Obtenido |", "| --- | --- | --- |"]
        md += [f"| {x['prueba']} | {x['esperado']} | {'✅' if x['ok'] else '❌'} {x['obtenido']} |" for x in informe[clave]]
    md += ["", "## Manejo de errores", ""] + [f"- {'✅' if x['ok'] else '❌'} {x['prueba']} (obtenido: {x['obtenido']})"
                                               for x in informe["errores"]]
    with open(base + ".md", "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")

    print("\n================ RESUMEN ================")
    print(f"Consulta {resumen['api'][0]}/{resumen['api'][1]} · Seguridad {resumen['seguridad'][0]}/{resumen['seguridad'][1]} · "
          f"Errores {resumen['errores'][0]}/{resumen['errores'][1]} · Dashboard {resumen['dashboard'][0]}/{resumen['dashboard'][1]}")
    h = resumen["herramientas"]
    print(f"Herramientas: {h['OK']} OK · {h['REVISAR']} revisar · {h['FALLO']} fallo · {h['TIEMPO']} tiempo agotado")
    print(f"Informe: {os.path.abspath(base + '.md')}\n         {os.path.abspath(base + '.json')}")


if __name__ == "__main__":
    main()
