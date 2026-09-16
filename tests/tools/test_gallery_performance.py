"""Exercise the Gallery performance CLI's evidence-to-exit-status contract."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

COMMAND = Path(__file__).resolve().parents[2] / "scripts/run-gallery-performance.py"


class GalleryPerformanceCLI(unittest.TestCase):
    def report(self):
        return {
            "status": "completed", "trace": False, "foreground_required": True,
            "samples": [
                {"label": label, "method": method, "set": group,
                 "wall_ms": 20, "target_ms": 50, "hard_limit_ms": 500,
                 "correct": True, "environment_stable": True,
                 "before": {"foreground": True}, "after": {"foreground": True}}
                for group in (1, 2, 3)
                for label in ("Review interactions", "Activity", "More", "Quick help")
                for method in ("callback", "keyboard", "mouse")
            ],
        }

    def summarize(self, report):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "result.json"
            file.write_text(json.dumps(report))
            return subprocess.run(
                [sys.executable, str(COMMAND), "--summarize", str(file)],
                capture_output=True, text=True, check=False)

    def test_complete_functional_run_can_fail_latency(self):
        report = self.report()
        report["samples"][2]["wall_ms"] = 650
        result = self.summarize(report)
        self.assertEqual(result.returncode, 1)
        self.assertIn("over_500ms=1", result.stdout)

    def test_background_and_incomplete_results_are_invalid(self):
        report = self.report()
        report["samples"][1]["before"]["foreground"] = False
        self.assertEqual(self.summarize(report).returncode, 2)
        report = self.report()
        report["samples"].pop()
        self.assertEqual(self.summarize(report).returncode, 2)

    def test_valid_and_diagnostic_results_are_distinguished(self):
        report = self.report()
        self.assertEqual(self.summarize(report).returncode, 0)
        report["trace"] = True
        report["samples"][0]["wall_ms"] = 700
        result = self.summarize(report)
        self.assertEqual(result.returncode, 0)
        self.assertIn("not acceptance samples", result.stdout)
