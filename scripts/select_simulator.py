"""Choose an installed, available iPhone on iOS 17+, never guess a device name."""
import json
import re
import sys


def model_rank(name):
    """Prefer a recent numbered iPhone, then Pro, over SE or an unnamed device."""
    if "SE" in name:
        generation = 0
    else:
        match = re.search(r"iPhone\s+(\d+)", name)
        generation = int(match.group(1)) if match else 1
    if "Pro Max" in name:
        variant = 2
    elif "Pro" in name:
        variant = 1
    else:
        variant = 0
    return (generation, variant)


def select_device(payload):
    candidates = []
    for runtime, devices in payload.get("devices", {}).items():
        version = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if not version or int(version.group(1)) < 17:
            continue
        rank = tuple(int(part or 0) for part in version.groups())
        for device in devices:
            name = device.get("name", "")
            if device.get("isAvailable") is True and name.startswith("iPhone"):
                identifier = device.get("udid", "")
                if re.fullmatch(r"[0-9a-fA-F-]{36}", identifier):
                    candidates.append((rank, model_rank(name), name, identifier))
    if not candidates:
        raise ValueError("No available iPhone simulator with iOS 17 or newer was found.")
    return sorted(candidates, reverse=True)[0][3]


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as stream:
        print(select_device(json.load(stream)))
