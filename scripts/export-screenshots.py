#!/usr/bin/env python3
"""Collect simulator PNGs written by the UI tests and any attachments inside the xcresult."""
import json
import subprocess
import sys
from pathlib import Path


def export_legacy(bundle: Path, destination: Path) -> int:
    summary = subprocess.run(
        ["xcrun", "xcresulttool", "get", "object", "--legacy", "--path", str(bundle), "--format", "json"],
        check=False, capture_output=True, text=True,
    )
    if summary.returncode != 0:
        summary = subprocess.run(
            ["xcrun", "xcresulttool", "get", "--legacy", "--path", str(bundle), "--format", "json"],
            check=False, capture_output=True, text=True,
        )
    if summary.returncode != 0 or not summary.stdout.strip():
        return 0
    saved = 0
    seen = set()

    def walk(node):
        if isinstance(node, dict):
            filename = None
            payload = None
            if isinstance(node.get("filename"), dict):
                filename = node["filename"].get("_value")
            if isinstance(node.get("payloadRef"), dict):
                payload = node["payloadRef"].get("id")
            if filename and payload and payload not in seen and str(filename).lower().endswith((".png", ".jpg", ".jpeg")):
                seen.add(payload)
                target = destination / f"xcresult-{saved_name(filename, payload)}"
                exported = subprocess.run(
                    ["xcrun", "xcresulttool", "get", "object", "--legacy", "--path", str(bundle), "--id", payload, "--output-path", str(target)],
                    check=False, capture_output=True,
                )
                if exported.returncode != 0 or not target.exists():
                    subprocess.run(
                        ["xcrun", "xcresulttool", "export", "--type", "file", "--path", str(bundle), "--id", payload, "--output-path", str(target)],
                        check=False, capture_output=True,
                    )
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    try:
        walk(json.loads(summary.stdout))
    except json.JSONDecodeError:
        return 0
    return len(list(destination.glob("xcresult-*")))


def saved_name(filename: str, payload: str) -> str:
    clean = "".join(character if character.isalnum() or character in ".-_" else "-" for character in filename)
    return f"{payload[:8]}-{clean}"


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "ci-results")
    destination = root / "screenshots"
    destination.mkdir(parents=True, exist_ok=True)
    bundle = root / "ScreenMind.xcresult"
    if bundle.exists():
        modern = subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", str(destination / "attachments")],
            check=False, capture_output=True, text=True,
        )
        if modern.returncode != 0:
            export_legacy(bundle, destination)
    pngs = list(destination.rglob("*.png"))
    print(f"Simulator screenshots: {len(pngs)} under {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
