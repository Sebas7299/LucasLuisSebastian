import base64
import hashlib
import hmac
import json
import os
import sys
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SIMULADOR_DIR = os.path.join(ROOT_DIR, "simulador")
if SIMULADOR_DIR not in sys.path:
    sys.path.insert(0, SIMULADOR_DIR)

import simular_orquestador as sim


class TestSimuladorAuth(unittest.TestCase):
    def test_firmar_genera_hmac_sha256_esperado(self):
        token = "secreto-de-prueba"
        body = b'{"herramienta":"ls"}'
        headers = sim.firmar(token, "POST", "/proxy/ejecutar", body, timestamp="1700000000")

        esperado_msg = b"POST:/proxy/ejecutar:1700000000:" + body
        esperada = hmac.new(token.encode(), esperado_msg, hashlib.sha256).hexdigest()

        self.assertEqual(headers["X-Signature"], esperada)
        self.assertEqual(headers["X-Timestamp"], "1700000000")
        self.assertEqual(headers["Content-Type"], "application/json")

    def test_firmar_cambia_si_cambia_cuerpo_o_metodo(self):
        h1 = sim.firmar("tok", "GET", "/proxy/herramientas", b"", timestamp="1700000000")
        h2 = sim.firmar("tok", "POST", "/proxy/herramientas", b"", timestamp="1700000000")
        h3 = sim.firmar("tok", "GET", "/proxy/tareas", b"", timestamp="1700000000")
        self.assertNotEqual(h1["X-Signature"], h2["X-Signature"])
        self.assertNotEqual(h1["X-Signature"], h3["X-Signature"])

    def test_crear_jwt_hs256_estructura_y_firma_valida(self):
        token = "clave-jwt"
        payload = {"runner_id": "runner-1", "exp": 1999999999}
        jwt_str = sim.crear_jwt(token, payload)
        partes = jwt_str.split(".")
        self.assertEqual(len(partes), 3)

        def decode_b64(seg: str) -> dict:
            pad = "=" * (-len(seg) % 4)
            return json.loads(base64.urlsafe_b64decode(seg + pad).decode("utf-8"))

        self.assertEqual(decode_b64(partes[0]), {"alg": "HS256", "typ": "JWT"})
        self.assertEqual(decode_b64(partes[1]), payload)

        firma_esperada = sim._b64url(
            hmac.new(token.encode(), f"{partes[0]}.{partes[1]}".encode(), hashlib.sha256).digest()
        )
        self.assertEqual(partes[2], firma_esperada)


if __name__ == "__main__":
    unittest.main()
