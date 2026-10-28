#!/usr/bin/env python3
"""Check that invalid packaging inputs preserve the last built application."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class PackagingChecks(unittest.TestCase):
    def check_rejected_input(self, missing):
        with tempfile.TemporaryDirectory(prefix='qingtie-packaging-checks-') as directory:
            root = Path(directory)
            script = root / 'scripts/package-app.py'
            script.parent.mkdir()
            shutil.copyfile(Path(__file__).resolve().parents[1] / 'scripts/package-app.py', script)
            binary = root / 'dist/QingTie.app/Contents/MacOS/QingTie'
            binary.parent.mkdir(parents=True)
            original = b'preserve the previous application'
            binary.write_bytes(original)
            source = root / 'missing-executable' if missing else binary
            result = subprocess.run([sys.executable, str(script), '--executable', str(source)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(binary.is_file(), 'Invalid input deleted the previous application')
            self.assertEqual(binary.read_bytes(), original)
            self.assertNotIn('Traceback', result.stderr, 'Invalid input should produce a usage error')

    def test_source_inside_output_preserves_previous_app(self):
        self.check_rejected_input(missing=False)

    def test_missing_source_preserves_previous_app(self):
        self.check_rejected_input(missing=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
