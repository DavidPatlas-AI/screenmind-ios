"""Choose an installed, available iPhone on iOS 17+, never guess a device name."""
import json
import re
import sys


def select_device(payload):
    candidates = []
    for runtime, devices in payload.get("devices", {}).items():
        version = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if not version or int(version.group(1)) < 17:
            continue
        rank = tuple(int(part or 0) for part in version.groups())
        for device in devices:
            if device.get("isAvailable") is True and device.get("name", "").startswith("iPhone"):
                identifier = device.get("udid", "")
                if re.fullmatch(r"[0-9a-fA-F-]{36}", identifier):
                    candidates.append((rank, identifier))
    if not candidates:
        raise ValueError("No available iPhone simulator with iOS 17 or newer was found.")
    return sorted(candidates, reverse=True)[0][1]


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as stream:
        print(select_device(json.load(stream)))
