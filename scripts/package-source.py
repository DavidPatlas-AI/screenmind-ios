"""Package only source/configuration/docs, including the hidden workflow directory."""
from pathlib import Path
import hashlib
import zipfile

root = Path(__file__).resolve().parent.parent
allowed_directories = {"ScreenMind", "Shared", "ShareExtension", "ScreenMindTests", "ScreenMind.xcodeproj", "scripts", ".github"}
allowed_suffixes = {".swift", ".plist", ".entitlements", ".xcprivacy", ".png", ".json", ".mjs", ".py", ".sh", ".xcscheme", ".pbxproj", ".yml", ".md"}
files = []
for file in root.rglob("*"):
    if not file.is_file() or file.is_symlink():
        continue
    relative = file.relative_to(root)
    if {"build", "DerivedData", "xcuserdata", "__pycache__", "ci-results"}.intersection(relative.parts):
        continue
    if len(relative.parts) > 1 and relative.parts[0] not in allowed_directories:
        continue
    if file.suffix not in allowed_suffixes and file.name != ".gitignore":
        continue
    files.append(file)

for name in ["ScreenMind-iOS-Source.zip", "ScreenMind-iOS-Cloud.zip"]:
    target = root.parent / name
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(files):
            archive.write(file, file.relative_to(root).as_posix())
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        assert ".github/workflows/ios-simulator.yml" in archive.namelist()
        assert "ScreenMind/ReviewFlow.swift" in archive.namelist()
        assert not any(".env" in entry or "xcuserdata" in entry for entry in archive.namelist())
    print(f"{name}: {len(files)} source files, SHA-256 {hashlib.sha256(target.read_bytes()).hexdigest()}")
