import io
import os
import sys
import unittest
from contextlib import redirect_stdout
from unittest import mock

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SIMULADOR_DIR = os.path.join(ROOT_DIR, "simulador")
if SIMULADOR_DIR not in sys.path:
    sys.path.insert(0, SIMULADOR_DIR)

import simular_orquestador as sim


class TestSimuladorFlujo(unittest.TestCase):
    def test_firmado_omite_query_string_en_hmac(self):
        capturado = {}

        def fake_http(base, method, path, headers, body=b""):
            capturado["path"] = path
            capturado["headers"] = headers
            return 200, []

        with mock.patch.object(sim, "http", side_effect=fake_http):
            sim.firmado("http://127.0.0.1:8000", "tok", "GET", "/proxy/tareas?limite=5")

        self.assertEqual(capturado["path"], "/proxy/tareas?limite=5")
        esperado = sim.firmar(
            "tok",
            "GET",
            "/proxy/tareas",
            b"",
            timestamp=capturado["headers"]["X-Timestamp"],
        )
        self.assertEqual(capturado["headers"]["X-Signature"], esperado["X-Signature"])

    def test_ejecutar_escenario_exitoso_y_rechazo_gateway(self):
        escenario = {
            "nombre": "Listar raíz",
            "herramienta": "ls",
            "params": {"ruta": "/"},
            "espera_estado": "completado",
        }
        respuestas = [
            (200, {"tarea_id": 10, "estado": "pendiente"}),
            (200, {"estado": "corriendo"}),
            (200, {"estado": "completado", "codigo_salida": 0, "resultado": {"raw_output": "bin\netc"}}),
        ]
        with mock.patch.object(sim, "firmado", side_effect=respuestas), mock.patch.object(sim.time, "sleep"):
            with redirect_stdout(io.StringIO()):
                ok = sim.ejecutar_escenario("http://127.0.0.1:8000", "tok", 1, escenario, orden=1, poll_interval=0.1)
        self.assertTrue(ok)

        with mock.patch.object(sim, "firmado", return_value=(401, {"detail": "unauthorized"})):
            with redirect_stdout(io.StringIO()):
                ok_fail = sim.ejecutar_escenario("http://127.0.0.1:8000", "tok", 1, escenario, orden=2)
        self.assertFalse(ok_fail)

    def test_pruebas_seguridad_pasa_con_respuestas_esperadas(self):
        codigos = iter([
            (401, {}), (401, {}), (401, {}), (200, []),
            (403, {}), (401, {}), (401, {}), (200, []),
        ])
        with mock.patch.object(sim, "http", side_effect=lambda *a, **kw: next(codigos)):
            with redirect_stdout(io.StringIO()):
                self.assertTrue(sim.pruebas_seguridad("http://127.0.0.1:8000", "tok"))


if __name__ == "__main__":
    unittest.main()
