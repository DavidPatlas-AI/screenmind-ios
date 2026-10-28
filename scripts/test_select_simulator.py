import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from select_simulator import select_device


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_newest_available_iphone(self):
        def device(name, identifier, available=True):
            return {"name": name, "udid": identifier, "isAvailable": available}
        old = "11111111-1111-4111-8111-111111111111"
        chosen = "22222222-2222-4222-8222-222222222222"
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [device("iPhone old", old)],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [device("iPhone new", chosen), device("iPad", old)],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [device("iPhone unavailable", old, False)],
        }}
        self.assertEqual(select_device(payload), chosen)

    def test_rejects_missing_or_unsupported_simulators(self):
        for payload in [{}, {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-16-4": []}}]:
            with self.assertRaises(ValueError):
                select_device(payload)

    def test_rejects_invalid_identifier(self):
        with self.assertRaises(ValueError):
            select_device({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"name": "iPhone", "isAvailable": True, "udid": "not-a-device-id"}
            ]}})


if __name__ == "__main__":
    unittest.main()
