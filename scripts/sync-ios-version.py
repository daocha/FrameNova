#!/usr/bin/env python3
"""Keep shared release version settings aligned before project generation."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / "android/app/build.gradle.kts").read_text()
version = re.search(r'versionName\s*=\s*"([^"]+)"', source)
code = re.search(r'versionCode\s*=\s*(\d+)', source)
if version is None or code is None:
    raise SystemExit("Cannot read the release version and build number.")
content = (
    "// Synchronized from the shared release settings during project generation.\n"
    f"MARKETING_VERSION = {version.group(1)}\n"
    f"CURRENT_PROJECT_VERSION = {code.group(1)}\n"
)
destination = root / "ios/Config/Version.xcconfig"
if not destination.exists() or destination.read_text() != content:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(content)
