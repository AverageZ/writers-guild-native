#!/usr/bin/env python3
"""Package the locally built Swift executable and SwiftPM resource bundles."""
from pathlib import Path
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
bin_path = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip())
app = root / "build" / "WritersGuild.app"
contents = app / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Resources").mkdir(parents=True, exist_ok=True)
shutil.copy2(bin_path / "WritersGuild", contents / "MacOS" / "WritersGuild")
for bundle in bin_path.glob("*.bundle"):
    shutil.copytree(bundle, contents / "Resources" / bundle.name, dirs_exist_ok=True)
info = {
    "CFBundleExecutable": "WritersGuild",
    "CFBundleIdentifier": "local.writersguild.native",
    "CFBundleName": "Writers Guild",
    "CFBundleDisplayName": "Writers Guild",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
}
with (contents / "Info.plist").open("wb") as file:
    plistlib.dump(info, file)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
print(app)
