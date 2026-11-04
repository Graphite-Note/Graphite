#!/usr/bin/env python3
"""Print the identifier (UDID) of an available iPad simulator, for the `hosted-ipad` job of .github/workflows/ci.yml.

Reads `xcrun simctl list devices available --json`, prefers the newest iOS runtime and, inside it, the model the hosted
suite is written for, an 11-inch iPad Pro (the owner's iPad), then another iPad Pro, an 11-inch iPad Air, any other iPad
and the iPad mini last. The tests measure a regular-width window that has room for the tab bar's tools; the mini's 744-point
window has not, so choosing it (as "iPad mini (A17 Pro)" contains "Pro") fails them. Exits with status 1 and a message when no iPad simulator exists, so the job
fails with a clear reason rather than with an xcodebuild destination error.

The runtime of the installed iOS Simulator SDK comes first: a runner image has had iPads only on an older runtime, which
xcodebuild then refused as a destination ("The iOS 27.0 simulator runtime is not available"). When that runtime has no
iPad, one is created on it, of the preferred model.

Usage:
  python3 scripts/select-ipad-simulator.py            prints the UDID
"""
import json
import re
import subprocess
import sys


def runtime_sort_key(runtime_identifier):
    """Sort key from `com.apple.CoreSimulator.SimRuntime.iOS-27-0` so that iOS 27.0 sorts after iOS 18.4."""
    match = re.search(r"iOS-(\d+)-(\d+)", runtime_identifier)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


def model_preference(device):
    """Sort key: smaller is preferred. Newer chips first inside a model, by their position in the name."""
    name = device["name"]
    if name.startswith("iPad Pro 11-inch"):
        rank = 0
    elif name.startswith("iPad Pro"):
        rank = 1
    elif name.startswith("iPad Air 11-inch"):
        rank = 2
    elif "mini" in name:
        rank = 4
    else:
        rank = 3
    # M5 before M4: the highest number in the name, negated.
    chip_numbers = [int(number) for number in re.findall(r"\(M(\d+)\)", name)]
    return (rank, -max(chip_numbers, default=0), name)


def simulator_json(*arguments):
    return json.loads(subprocess.run(["xcrun", "simctl", "list", *arguments, "--json"],
                                     capture_output=True, text=True, check=True).stdout)


def runtime_of_the_installed_sdk():
    """The available iOS runtime whose version is the iOS Simulator SDK's, or None."""
    sdk_version = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
                                 capture_output=True, text=True).stdout.strip()
    runtimes = [runtime for runtime in simulator_json("runtimes")["runtimes"]
                if runtime.get("platform", "iOS") == "iOS" and runtime.get("isAvailable", False)
                and runtime_sort_key(runtime["identifier"]) != (0, 0)]
    matching = [runtime for runtime in runtimes if runtime.get("version") == sdk_version]
    # A runtime made for one device family (`iOS-27-2-iPhone19-4`) holds no iPad: the plain one first.
    matching.sort(key=lambda runtime: len(runtime["identifier"]))
    return matching[0]["identifier"] if matching else None


def ipad_created_on(runtime_identifier):
    """Creates an iPad of the preferred model on the runtime and returns its UDID, or None."""
    device_types = [device_type for device_type in simulator_json("devicetypes")["devicetypes"]
                    if device_type.get("productFamily") == "iPad" or "iPad" in device_type["name"]]
    if not device_types:
        return None
    device_type = min(device_types, key=model_preference)
    created = subprocess.run(["xcrun", "simctl", "create", device_type["name"], device_type["identifier"], runtime_identifier],
                             capture_output=True, text=True)
    return created.stdout.strip() if created.returncode == 0 and created.stdout.strip() else None


def main():
    devices_by_runtime = simulator_json("devices", "available")["devices"]
    sdk_runtime = runtime_of_the_installed_sdk()
    if sdk_runtime is not None:
        ipads = [device for device in devices_by_runtime.get(sdk_runtime, [])
                 if "iPad" in device["name"] and device.get("isAvailable", True)]
        udid = min(ipads, key=model_preference)["udid"] if ipads else ipad_created_on(sdk_runtime)
        if udid:
            print(udid)
            return 0
    for runtime_identifier in sorted(devices_by_runtime, key=runtime_sort_key, reverse=True):
        if "iOS" not in runtime_identifier:
            continue
        ipads = [device for device in devices_by_runtime[runtime_identifier]
                 if "iPad" in device["name"] and device.get("isAvailable", True)]
        if not ipads:
            continue
        print(min(ipads, key=model_preference)["udid"])
        return 0
    print("no available iPad simulator; install an iOS simulator runtime and create an iPad device", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
