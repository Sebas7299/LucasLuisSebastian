#!/usr/bin/env python3
"""Simulador del Orquestador para eth-runner.

Emula las peticiones que el Orquestador central le enviaría al runner,
firmándolas con HMAC-SHA256 exactamente igual que en producción. Sirve para
probar el runner de punta a punta SIN tener todavía el Orquestador real.

Solo usa la librería estándar de Python (urllib), así que no hay que instalar
nada en el host.

Modos de uso:

  # 1. Flujo rápido: crea usuario/objetivo/sesión y corre un escenario suelto
  python3 simular_orquestador.py escenario escenarios/01_ls_raiz.json

  # 2. Corre TODOS los escenarios de una carpeta, uno tras otro
  python3 simular_orquestador.py escenarios escenarios/

  # 3. Pruebas de seguridad de la autenticación del runner (HMAC + pase JWT)
  python3 simular_orquestador.py seguridad

Opciones:
  --url URL         URL base del gateway (default: http://127.0.0.1:8000)
  --env-file RUTA   .env de donde leer INTERNAL_API_TOKEN (default: ../.env)
  --token TOKEN     Token directo (tiene prioridad sobre --env-file)

El runner, en modo local, no publica puertos. Para que este simulador llegue
al gateway desde el host, publica el puerto SOLO en localhost con un override
(ver README_SIMULADOR.md). Si prefieres no publicar puertos, también puedes
correr este script dentro del contenedor del gateway.
"""

import argparse
import base64
import glob
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request


# --------------------------------------------------------------------------
# Utilidades de configuración
# --------------------------------------------------------------------------

def cargar_token(args) -> str:
    if args.token:
        return args.token.strip()
    env = os.environ.get("INTERNAL_API_TOKEN", "").strip()
    if env:
        return env
    # Leer del .env
    ruta = args.env_file
    if os.path.exists(ruta):
        for linea in open(ruta, encoding="utf-8"):
            linea = linea.strip()
            if linea.startswith("INTERNAL_API_TOKEN="):
                return linea.split("=", 1)[1].strip()
    sys.exit(
        "❌ No encontré INTERNAL_API_TOKEN. Pásalo con --token, expórtalo como "
        "variable de entorno, o apunta --env-file al .env correcto."
    )


# --------------------------------------------------------------------------
# Firma y llamadas HTTP (como el Orquestador)
# --------------------------------------------------------------------------

def firmar(token: str, method: str, path: str, body: bytes, timestamp: str = None) -> dict:
    """Construye las cabeceras HMAC. El mensaje firmado es
    METHOD:PATH:TIMESTAMP: + BODY, idéntico a shared/internal_auth.py."""
    ts = timestamp if timestamp is not None else str(int(time.time()))
    msg = f"{method}:{path}:{ts}:".encode() + body
    sig = hmac.new(token.encode(), msg, hashlib.sha256).hexdigest()
    return {"X-Signature": sig, "X-Timestamp": ts, "Content-Type": "application/json"}


def http(base: str, method: str, path: str, headers: dict, body: bytes = b""):
    req = urllib.request.Request(base + path, data=body or None, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            try:
                return r.status, json.loads(raw or b"null")
            except json.JSONDecodeError:
                return r.status, raw.decode(errors="replace")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"null")
        except json.JSONDecodeError:
            return e.code, raw.decode(errors="replace")
    except urllib.error.URLError as e:
        sys.exit(
            f"❌ No pude conectar a {base}{path}: {e}\n"
            "   ¿Está levantado el runner y publicado el puerto en 127.0.0.1? "
            "Ver README_SIMULADOR.md."
        )


def firmado(base: str, token: str, method: str, path: str, payload=None):
    body = json.dumps(payload, separators=(",", ":")).encode() if payload is not None else b""
    return http(base, method, path, firmar(token, method, path, body), body)


# --------------------------------------------------------------------------
# Flujo de ejecución de herramientas
# --------------------------------------------------------------------------

def preparar_sesion(base: str, token: str, etiqueta: str = "simulador"):
    """Crea (o reutiliza) usuario, objetivo y sesión. Devuelve sesion_id."""
    st, u = firmado(base, token, "POST", "/usuarios/", {"external_id": etiqueta, "nombre": etiqueta})
    if st != 200:
        sys.exit(f"❌ No pude crear el usuario ({st}): {u}")
    st, o = firmado(base, token, "POST", "/objetivos/",
                    {"usuario_id": u["usuario_id"], "url_objetivo": "laboratorio-local"})
    if st != 200:
        sys.exit(f"❌ No pude crear el objetivo ({st}): {o}")
    st, s = firmado(base, token, "POST", "/sesiones/", {"objetivo_id": o["objetivo_id"]})
    if st != 200:
        sys.exit(f"❌ No pude crear la sesión ({st}): {s}")
    return s["sesion_id"]


def ejecutar_escenario(base: str, token: str, sesion_id: int, escenario: dict, orden: int):
    nombre = escenario.get("nombre", escenario.get("herramienta", "sin nombre"))
    herramienta = escenario["herramienta"]
    params = escenario.get("params", {})

    print(f"\n──────── Escenario: {nombre}")
    print(f"  herramienta: {herramienta}  params: {json.dumps(params, ensure_ascii=False)}")

    st, t = firmado(base, token, "POST", "/proxy/ejecutar", {
        "herramienta": herramienta,
        "params": params,
        "sesion_id": sesion_id,
        "orden_ejecucion": orden,
    })
    if st != 200:
        print(f"  ❌ El gateway rechazó la ejecución ({st}): {t}")
        return False

    tarea_id = t.get("tarea_id")
    print(f"  tarea #{tarea_id} encolada (estado: {t.get('estado')})")

    # Poll
    r = {}
    for _ in range(45):
        st, r = firmado(base, token, "GET", f"/proxy/tareas/{tarea_id}")
        estado = r.get("estado") if isinstance(r, dict) else None
        if estado in ("completado", "fallido"):
            break
        time.sleep(2)

    estado = r.get("estado") if isinstance(r, dict) else "?"
    codigo = r.get("codigo_salida") if isinstance(r, dict) else "?"
    print(f"  estado final: {estado}  (código de salida: {codigo})")

    esperado = escenario.get("espera_estado", "completado")
    ok = estado == esperado
    print("  ✅ Resultado esperado." if ok else f"  ❌ Se esperaba '{esperado}'.")

    resultado = r.get("resultado") if isinstance(r, dict) else None
    if resultado:
        raw = resultado.get("raw_output", "")
        print(f"  salida (recortada): {str(raw)[:300]}")
    return ok


# --------------------------------------------------------------------------
# Pruebas de seguridad de la autenticación del runner
# --------------------------------------------------------------------------

def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def crear_jwt(token: str, payload: dict) -> str:
    """Crea un JWT HS256 a mano (sin PyJWT), firmado con el token interno.
    Sirve para probar el pase del dashboard que normalmente emite el
    Orquestador."""
    header = {"alg": "HS256", "typ": "JWT"}
    h = _b64url(json.dumps(header, separators=(",", ":")).encode())
    p = _b64url(json.dumps(payload, separators=(",", ":")).encode())
    firma = hmac.new(token.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest()
    return f"{h}.{p}.{_b64url(firma)}"


def pruebas_seguridad(base: str, token: str):
    print("=== Pruebas de seguridad de la autenticación del runner ===")
    resultados = []

    def chequear(nombre, status_real, status_esperado):
        ok = status_real == status_esperado
        icono = "✅" if ok else "❌"
        print(f"  {icono} {nombre}: HTTP {status_real} (esperado {status_esperado})")
        resultados.append(ok)

    path = "/proxy/herramientas"

    # 1. Sin cabeceras de firma -> 401
    st, _ = http(base, "GET", path, {})
    chequear("Petición sin firma", st, 401)

    # 2. Firma inválida -> 401
    bad = {"X-Signature": "0" * 64, "X-Timestamp": str(int(time.time())), "Content-Type": "application/json"}
    st, _ = http(base, "GET", path, bad)
    chequear("Firma HMAC inválida", st, 401)

    # 3. Timestamp vencido (más de 5 min) -> 401
    viejo = str(int(time.time()) - 600)
    st, _ = http(base, "GET", path, firmar(token, "GET", path, b"", timestamp=viejo))
    chequear("Timestamp vencido (replay)", st, 401)

    # 4. Firma válida -> 200 (control: debe PASAR)
    st, _ = firmado(base, token, "GET", path)
    chequear("Firma válida (control)", st, 200)

    # 5. Pase JWT: /findings sin token -> 403 (falta Authorization)
    st, _ = http(base, "GET", "/findings", {})
    chequear("Dashboard sin pase JWT", st, 403)

    # 6. Pase JWT sin claim exp -> 401 (el runner exige exp)
    jwt_sin_exp = crear_jwt(token, {"runner_id": "cualquiera"})
    st, _ = http(base, "GET", "/findings", {"Authorization": f"Bearer {jwt_sin_exp}"})
    chequear("Pase JWT sin expiración", st, 401)

    # 7. Pase JWT vencido -> 401
    jwt_vencido = crear_jwt(token, {"exp": int(time.time()) - 60})
    st, _ = http(base, "GET", "/findings", {"Authorization": f"Bearer {jwt_vencido}"})
    chequear("Pase JWT vencido", st, 401)

    # 8. Pase JWT válido (con exp futuro) -> 200 (en local RUNNER_ID está vacío,
    #    así que no se exige el claim runner_id)
    jwt_ok = crear_jwt(token, {"exp": int(time.time()) + 300})
    st, _ = http(base, "GET", "/findings", {"Authorization": f"Bearer {jwt_ok}"})
    chequear("Pase JWT válido (control)", st, 200)

    total = len(resultados)
    ok = sum(resultados)
    print(f"\nResultado: {ok}/{total} comprobaciones de seguridad pasaron.")
    return ok == total


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Simulador del Orquestador para eth-runner")
    ap.add_argument("--url", default="http://127.0.0.1:8000", help="URL base del gateway")
    ap.add_argument("--env-file", default=os.path.join(os.path.dirname(__file__), "..", ".env"))
    ap.add_argument("--token", default="")

    sub = ap.add_subparsers(dest="modo", required=True)
    s1 = sub.add_parser("escenario", help="Correr un escenario JSON")
    s1.add_argument("archivo")
    s2 = sub.add_parser("escenarios", help="Correr todos los escenarios de una carpeta")
    s2.add_argument("carpeta")
    sub.add_parser("seguridad", help="Pruebas de autenticación del runner")

    args = ap.parse_args()
    token = cargar_token(args)
    base = args.url.rstrip("/")

    if args.modo == "seguridad":
        ok = pruebas_seguridad(base, token)
        sys.exit(0 if ok else 1)

    # Modos de ejecución de herramientas
    if args.modo == "escenario":
        archivos = [args.archivo]
    else:
        archivos = sorted(glob.glob(os.path.join(args.carpeta, "*.json")))
        if not archivos:
            sys.exit(f"❌ No encontré escenarios .json en {args.carpeta}")

    print(f"Preparando sesión en {base} ...")
    sesion_id = preparar_sesion(base, token)
    print(f"  sesión #{sesion_id} lista.")

    resultados = []
    for i, ruta in enumerate(archivos, start=1):
        with open(ruta, encoding="utf-8") as f:
            escenario = json.load(f)
        resultados.append(ejecutar_escenario(base, token, sesion_id, escenario, orden=i))

    print(f"\n==================== Resumen: {sum(resultados)}/{len(resultados)} escenarios OK")
    sys.exit(0 if all(resultados) else 1)


if __name__ == "__main__":
    main()
