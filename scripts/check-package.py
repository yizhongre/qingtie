#!/usr/bin/env python3
"""Verify QingTie's package dependencies, app identity and system library links."""
from pathlib import Path
import argparse
import json
import plistlib
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=root / 'dist/QingTie.app')
arguments = parser.parse_args()
manifest = json.loads(subprocess.check_output(['swift', 'package', 'dump-package'], cwd=root))
assert manifest['dependencies'] == [], 'Unexpected external package dependencies'
app = arguments.app / 'Contents'
with (app / 'Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
for key, expected in {
    'CFBundleIdentifier': 'io.github.yizhongre.qingtie',
    'CFBundleName': 'QingTie',
    'CFBundleDisplayName': 'QingTie',
    'CFBundleExecutable': 'QingTie',
    'NSHumanReadableCopyright': '© 2026 QingTie',
}.items():
    assert info.get(key) == expected, f'Unexpected app identity: {key}'
resources = {str(path.relative_to(app / 'Resources'))
             for path in (app / 'Resources').rglob('*') if path.is_file()}
expected_resources = {
    'QingTie.icns', 'QingTieMark.png', 'QingTieMark@2x.png',
    'QingTieMenuTemplate.png', 'QingTieMenuTemplate@2x.png',
    'LICENSE',
}
assert resources == expected_resources, f'Unexpected packaged resources: {resources}'
assert {path.name for path in (app / 'MacOS').iterdir()} == {'QingTie'}, 'Unexpected packaged executables'
assert not (app / 'Frameworks').exists(), 'Unexpected bundled frameworks'
binary = app / 'MacOS/QingTie'
architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
assert architectures and set(architectures) <= {'arm64', 'x86_64'}, f'Unexpected architectures: {architectures}'
for architecture in architectures:
    links = subprocess.check_output(['otool', '-arch', architecture, '-L', str(binary)], text=True)
    libraries = [line.strip().split(' (', 1)[0] for line in links.splitlines() if line[:1].isspace()]
    assert libraries, f'No linked libraries found for {architecture}'
    for library in libraries:
        assert library.startswith(('/System/Library/', '/usr/lib/')), f'Non-system library in {architecture}: {library}'
print('PASS: no external package dependencies; QingTie app identity, resources and system library links verified')
