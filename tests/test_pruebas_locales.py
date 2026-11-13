import base64
import hashlib
import hmac
import json
import os
import sys
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PRUEBAS_DIR = os.path.join(ROOT_DIR, "pruebas")
if PRUEBAS_DIR not in sys.path:
    sys.path.insert(0, PRUEBAS_DIR)

import pruebas_locales as pl


class TestClientePruebasLocales(unittest.TestCase):
    def test_cliente_firmar_y_jwt(self):
        c = pl.Cliente("http://127.0.0.1:8000/", "token-secreto")
        self.assertEqual(c.base, "http://127.0.0.1:8000")

        headers = c.firmar("POST", "/proxy/ejecutar", b"{}", ts="1700000100")
        esperado = hmac.new(
            b"token-secreto",
            b"POST:/proxy/ejecutar:1700000100:{}",
            hashlib.sha256,
        ).hexdigest()
        self.assertEqual(headers["X-Signature"], esperado)
        self.assertEqual(headers["X-Timestamp"], "1700000100")

        jwt_token = c.jwt({"exp": 1800000000})
        h_b64, p_b64, s_b64 = jwt_token.split(".")
        header = json.loads(base64.urlsafe_b64decode(h_b64 + "=" * (-len(h_b64) % 4)))
        payload = json.loads(base64.urlsafe_b64decode(p_b64 + "=" * (-len(p_b64) % 4)))
        self.assertEqual(header, {"alg": "HS256", "typ": "JWT"})
        self.assertEqual(payload, {"exp": 1800000000})
        self.assertTrue(len(s_b64) > 0)


if __name__ == "__main__":
    unittest.main()
