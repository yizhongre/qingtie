#!/usr/bin/env python3
"""Verify the universal app and the contents of its downloadable disk image."""
from pathlib import Path
import hashlib
import os
import plistlib
import re
import subprocess
import sys


root = Path(__file__).resolve().parents[1]
app = root / 'dist/QingTie.app'
image = root / 'dist/QingTie-universal.dmg'
checksums = root / 'dist/SHA256SUMS.txt'


def check_app(bundle):
    binary = bundle / 'Contents/MacOS/QingTie'
    architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    assert set(architectures) == {'arm64', 'x86_64'}, f'Expected universal app, found {architectures}'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(bundle)], check=True)
    subprocess.run([sys.executable, str(root / 'scripts/check-package.py'), '--app', str(bundle)], check=True)
    with (bundle / 'Contents/Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    assert info['LSMinimumSystemVersion'] == '14.0', 'Unexpected minimum macOS version'
    assert set(p.name for p in (bundle / 'Contents').iterdir()) == {
        'Info.plist', 'MacOS', 'Resources', '_CodeSignature'
    }, 'Unexpected app bundle contents'
    assert (bundle / 'Contents/Resources/LICENSE').read_bytes() == (root / 'LICENSE').read_bytes(), 'License notice missing or changed'
    for architecture in architectures:
        commands = subprocess.check_output(['vtool', '-arch', architecture, '-show-build', str(binary)], text=True)
        assert re.search(r'\bminos\s+14\.0(?:\.0)?\s', commands), f'Unexpected deployment target for {architecture}'
    assert b'/Users/' not in binary.read_bytes(), 'Local source paths found in release executable'


def file_hashes(bundle):
    result = {}
    for path in bundle.rglob('*'):
        assert not path.is_symlink(), f'Unexpected symlink inside app: {path.relative_to(bundle)}'
        if path.is_file():
            result[str(path.relative_to(bundle))] = (
                hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode & 0o777
            )
    return result


check_app(app)
assert image.is_file() and checksums.is_file(), 'Build the disk image and checksums first'
digest = hashlib.sha256(image.read_bytes()).hexdigest()
assert checksums.read_text() == f'{digest}  {image.name}\n', 'Disk image checksum does not match'
subprocess.run(['hdiutil', 'verify', str(image)], check=True)
mounted = plistlib.loads(subprocess.check_output([
    'hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-plist', str(image)
]))
entities = mounted['system-entities']
device = next(entry['dev-entry'] for entry in entities if 'dev-entry' in entry)
try:
    volume = Path(next(entry['mount-point'] for entry in entities if 'mount-point' in entry))
    system_entries = {'.fseventsd', '.Trashes', '.Spotlight-V100', '.HFS+ Private Directory Data\r'}
    assert {p.name for p in volume.iterdir()} - system_entries == {'QingTie.app', 'Applications'}, 'Unexpected disk image files'
    shortcut = volume / 'Applications'
    assert shortcut.is_symlink() and os.readlink(shortcut) == '/Applications', 'Applications shortcut missing or changed'
    installed_app = volume / 'QingTie.app'
    check_app(installed_app)
    assert file_hashes(installed_app) == file_hashes(app), 'Packaged app bytes or permissions changed'
finally:
    subprocess.run(['hdiutil', 'detach', device], check=True)

print('PASS: universal app, signatures, deployment targets, license, disk image contents and SHA-256 checksum verified')
