#!/usr/bin/env python3
"""Report what an archived Graphite app is made of, and fail when it grew past its budget.

Graphite is meant to stay a small core: extras are downloaded add-ons, not part of the app
(Docs/Architecture.md, Add-ons). This script measures an archived app (an .xcarchive or the
.app inside it), prints its main parts, and compares each with scripts/app-size-budget.json.
A part more than 1 % over its budget fails the check, so growth is a decision rather than an
accident. `scripts/archive-for-testflight.sh` runs it after archiving and stops before the
upload when it fails, unless it is given --allow-size-growth.

On-Demand Resources are counted as the App Store counts them: the asset packs of initial install
tags are downloaded and installed with the app, so they are part of its install size, while other
tags are not. Xcode puts an archive's asset packs beside the app, in Products/OnDemandResources
(a build folder's beside the .app, in OnDemandResources); a pack of an initial install tag is the
one whose Info.plist has a Priority of 1. The part `initialInstallTags` is their size, and `app`
is the bundle with them.

Usage:
  python3 scripts/app-size-budget.py <Graphite.xcarchive or Graphite.app>
  python3 scripts/app-size-budget.py <archive> --record   # make the measured sizes the new budget
  python3 scripts/app-size-budget.py --self-test           # check the counting on a made-up archive
"""
import argparse
import collections
import json
import os
import plistlib
import subprocess
import sys
import tempfile

BUDGET_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "app-size-budget.json")
TOLERANCE = 0.01


def folder_size(path):
    total = 0
    for directory, _, names in os.walk(path):
        for name in names:
            file_path = os.path.join(directory, name)
            if not os.path.islink(file_path):
                total += os.path.getsize(file_path)
    return total


def find_app(path):
    if path.endswith(".app"):
        return path
    applications = os.path.join(path, "Products", "Applications")
    for name in sorted(os.listdir(applications)):
        if name.endswith(".app"):
            return os.path.join(applications, name)
    sys.exit(f"No .app in {applications}")


# The Priority Xcode writes into the Info.plist of an asset pack whose tag is an initial install tag; packs of other
# tags have none, or a lower one for the prefetch order.
INITIAL_INSTALL_PRIORITY = 1


def asset_packs_installed_with(app):
    """{asset pack name: size} of the On-Demand Resources asset packs installed with the app: those of initial install tags.

    An archive keeps them in Products/OnDemandResources, a build folder in OnDemandResources beside the .app, and a
    build that embeds its asset packs inside the bundle, where they are already counted with it."""
    applications = os.path.dirname(app)
    candidates = [os.path.join(applications, "OnDemandResources"), os.path.join(os.path.dirname(applications), "OnDemandResources")]
    packs = {}
    for folder in candidates:
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            info_path = os.path.join(folder, name, "Info.plist")
            if not name.endswith(".assetpack") or not os.path.exists(info_path):
                continue
            with open(info_path, "rb") as info_file:
                priority = plistlib.load(info_file).get("Priority", 0)
            if priority >= INITIAL_INSTALL_PRIORITY:
                packs[name] = folder_size(os.path.join(folder, name))
    return packs


def measure(app):
    """The parts of the app: the whole install (the bundle with the initial install tags), the main binary, the asset
    catalog, the initial install tags, and each resource bundle and asset pack."""
    is_mac = os.path.isdir(os.path.join(app, "Contents"))
    contents = os.path.join(app, "Contents") if is_mac else app
    resources = os.path.join(contents, "Resources") if is_mac else app
    info = plistlib.load(open(os.path.join(contents, "Info.plist"), "rb"))
    binary = os.path.join(contents, "MacOS", info["CFBundleExecutable"]) if is_mac else os.path.join(app, info["CFBundleExecutable"])
    asset_catalog = os.path.join(resources, "Assets.car")
    installed_packs = asset_packs_installed_with(app)
    parts = {
        "app": folder_size(app) + sum(installed_packs.values()),
        "binary": os.path.getsize(binary),
        "assetCatalog": os.path.getsize(asset_catalog) if os.path.exists(asset_catalog) else 0,
        "initialInstallTags": sum(installed_packs.values()),
    }
    bundles = {name: folder_size(os.path.join(resources, name)) for name in sorted(os.listdir(resources)) if name.endswith(".bundle")}
    bundles.update(installed_packs)
    return ("macOS" if is_mac else "iOS"), parts, bundles, asset_catalog


def asset_catalog_groups(asset_catalog):
    """The asset catalog's renditions grouped by asset name, largest first."""
    if not os.path.exists(asset_catalog):
        return []
    result = subprocess.run(["xcrun", "assetutil", "--info", asset_catalog], capture_output=True, text=True)
    if result.returncode != 0:
        return []
    sizes = collections.Counter()
    for entry in json.loads(result.stdout):
        name = str(entry.get("Name", ""))
        if name:
            sizes[name.split("/")[0]] += entry.get("SizeOnDisk", 0)
    return sizes.most_common(8)


def megabytes(byte_count):
    return f"{byte_count / 1_000_000:6.1f} MB"


def self_test():
    """Measures a made-up iOS archive with one asset pack of an initial install tag and one of another tag."""
    def write(path, byte_count):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as file:
            file.write(b"x" * byte_count)

    def write_pack(folder, name, info, picture_bytes):
        write(os.path.join(folder, name, "Picture.jpg"), picture_bytes)
        with open(os.path.join(folder, name, "Info.plist"), "wb") as info_file:
            plistlib.dump(info, info_file)

    with tempfile.TemporaryDirectory() as archive:
        app = os.path.join(archive, "Products", "Applications", "Graphite.app")
        write(os.path.join(app, "Graphite"), 1000)
        with open(os.path.join(app, "Info.plist"), "wb") as info_file:
            plistlib.dump({"CFBundleExecutable": "Graphite"}, info_file)
        packs = os.path.join(archive, "Products", "OnDemandResources")
        write_pack(packs, "com.graphite.study.WelcomeTourPictures-1.assetpack", {"Priority": 1, "Tags": ["WelcomeTourPictures"]}, 300)
        write_pack(packs, "com.graphite.study.Later-2.assetpack", {"Tags": ["Later"]}, 5000)
        installed = asset_packs_installed_with(find_app(archive))
        _, parts, _, _ = measure(find_app(archive))
    bundle_bytes = 1000 + len(plistlib.dumps({"CFBundleExecutable": "Graphite"}))
    pack_bytes = 300 + len(plistlib.dumps({"Priority": 1, "Tags": ["WelcomeTourPictures"]}))
    problems = []
    if list(installed) != ["com.graphite.study.WelcomeTourPictures-1.assetpack"]:
        problems.append(f"the packs installed with the app are {list(installed)}, not the initial install tag's alone")
    if parts["initialInstallTags"] != pack_bytes:
        problems.append(f"initialInstallTags is {parts['initialInstallTags']} bytes, not {pack_bytes}")
    if parts["app"] != bundle_bytes + pack_bytes:
        problems.append(f"app is {parts['app']} bytes, not the bundle's {bundle_bytes} with the tag's {pack_bytes}")
    for problem in problems:
        print("SELF-TEST FAILED  " + problem)
    if not problems:
        print("Self-test passed: an initial install tag counts in the app's size, another tag does not.")
    return 1 if problems else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("path", nargs="?")
    parser.add_argument("--record", action="store_true", help="write the measured sizes as the new budget")
    parser.add_argument("--self-test", action="store_true", help="check the counting on a made-up archive")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    if arguments.path is None:
        parser.error("the archive or app to measure is required")

    platform, parts, bundles, asset_catalog = measure(find_app(arguments.path))
    print(f"{platform} app")
    for name, byte_count in parts.items():
        print(f"  {name:<20}{megabytes(byte_count)}")
    for name, byte_count in asset_catalog_groups(asset_catalog):
        print(f"    asset {name:<28}{megabytes(byte_count)}")
    for name, byte_count in sorted(bundles.items(), key=lambda item: -item[1])[:6]:
        kind = "pack" if name.endswith(".assetpack") else "bundle"
        print(f"    {kind} {name:<27}{megabytes(byte_count)}")

    budgets = json.load(open(BUDGET_PATH)) if os.path.exists(BUDGET_PATH) else {}
    if arguments.record:
        budgets[platform] = parts
        with open(BUDGET_PATH, "w") as budget_file:
            json.dump(budgets, budget_file, indent=2, sort_keys=True)
            budget_file.write("\n")
        print(f"Recorded the {platform} budget in {os.path.relpath(BUDGET_PATH)}.")
        return 0

    budget = budgets.get(platform)
    if budget is None:
        print(f"No {platform} budget yet: run with --record to make these sizes the budget.")
        return 1
    over = [name for name, byte_count in parts.items() if byte_count > budget.get(name, 0) * (1 + TOLERANCE)]
    for name in over:
        print(f"OVER BUDGET  {name}: {megabytes(parts[name])} against {megabytes(budget.get(name, 0))}")
    if over:
        print("Move the new resources into an add-on pack, or, if the growth is wanted, record a new budget with --record.")
        return 1
    print(f"Within the {platform} budget.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
