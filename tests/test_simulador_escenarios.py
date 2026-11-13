import os
import sys
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SIMULADOR_DIR = os.path.join(ROOT_DIR, "simulador")
if SIMULADOR_DIR not in sys.path:
    sys.path.insert(0, SIMULADOR_DIR)

import simular_orquestador as sim


class TestValidarEscenario(unittest.TestCase):
    def test_escenario_valido(self):
        data = {
            "nombre": "Listar raíz",
            "herramienta": "ls",
            "params": {"ruta": "/"},
            "espera_estado": "completado",
        }
        self.assertEqual(sim.validar_escenario(data), data)

    def test_rechaza_tipos_y_campos_invalidos(self):
        casos_invalidos = [
            ["no-es-dict"],
            {},
            {"herramienta": "   "},
            {"herramienta": "ls", "params": "no-dict"},
            {"herramienta": "ls", "espera_estado": "otro"},
        ]
        for caso in casos_invalidos:
            with self.subTest(caso=caso):
                with self.assertRaises(ValueError):
                    sim.validar_escenario(caso)


if __name__ == "__main__":
    unittest.main()
