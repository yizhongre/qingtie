#!/usr/bin/env python3
"""Package the QingTie executable, application metadata and icons."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--executable', type=Path, help='Use an already built executable')
arguments = parser.parse_args()
if arguments.executable is None:
    build = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=root, text=True).strip())
    executable = build / 'QingTie'
else:
    executable = arguments.executable.resolve()
if not executable.is_file():
    parser.error('The executable must be a regular file')
app = root / 'dist/QingTie.app'
if app.resolve() in executable.resolve().parents:
    parser.error('The executable must be outside the output app bundle')
if app.exists():
    shutil.rmtree(app)
resources = app / 'Contents/Resources'
macos = app / 'Contents/MacOS'
resources.mkdir(parents=True)
macos.mkdir()
shutil.copy2(executable, macos / 'QingTie')
shutil.copyfile(root / 'LICENSE', resources / 'LICENSE')
info = {
    'CFBundleIdentifier': 'io.github.yizhongre.qingtie',
    'CFBundleName': 'QingTie', 'CFBundleDisplayName': 'QingTie',
    'CFBundleExecutable': 'QingTie', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.3.0', 'CFBundleVersion': '7',
    'LSMinimumSystemVersion': '14.0', 'LSUIElement': True,
    'NSHighResolutionCapable': True, 'CFBundleIconFile': 'QingTie',
    'CFBundleDevelopmentRegion': 'zh-Hans',
    'NSHumanReadableCopyright': '© 2026 QingTie',
    'NSPrincipalClass': 'NSApplication'
}
with (app / 'Contents/Info.plist').open('wb') as handle:
    plistlib.dump(info, handle)
iconset = root / 'dist/QingTie.iconset'
if iconset.exists():
    shutil.rmtree(iconset)
subprocess.run(['swift', str(root / 'scripts/make-icon.swift'), str(iconset), str(resources)], check=True)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'QingTie.icns')], check=True)
print(app)
