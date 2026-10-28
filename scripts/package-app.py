#!/usr/bin/env python3
"""Package the QingTie executable, application metadata and icons."""
from pathlib import Path
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
build = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=root, text=True).strip())
app = root / 'dist/QingTie.app'
if app.exists():
    shutil.rmtree(app)
resources = app / 'Contents/Resources'
macos = app / 'Contents/MacOS'
resources.mkdir(parents=True)
macos.mkdir()
shutil.copy2(build / 'QingTie', macos / 'QingTie')
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
