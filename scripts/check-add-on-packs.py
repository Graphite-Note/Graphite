#!/usr/bin/env python3
"""Check that every add-on pack the app downloads matches the files at its pinned revision.

An add-on pack (`AddOnPack`) lists each file's name, size and SHA-256 and the commit it is
downloaded from. This script reads each pack definition in Sources, takes the files from that
commit with `git show`, and fails when a file is missing or its size or hash differ, so a
build can never ask for files that do not exist or no longer match.

The welcome tour's pictures also come with the app (Docs/App-size-todo.md, section 2): the iPad and
iPhone pack as an On-Demand Resources tag among the app target's initial install tags, the Mac pack in
the Mac app's bundle. The script checks that Graphite.xcodeproj takes exactly the pack's files that
way: each iPad and iPhone file for iOS only and with the pack's tag, each Mac file for macOS only and
with no tag, and the tag known to the project and named in ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS.

Usage:
  python3 scripts/check-add-on-packs.py
"""
import hashlib
import os
import re
import subprocess
import sys

REPOSITORY_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_DEFINITIONS = ["Sources/GraphiteUI/WelcomeTourScreenshotPack.swift"]
FILE_PATTERN = re.compile(r'AddOnFile\(name: "([^"]+)", byteCount: (\d+),\s*sha256: "([0-9a-f]{64})"\)')
PROJECT_PATH = "Graphite.xcodeproj/project.pbxproj"
BUILD_FILE_PATTERN = re.compile(r'/\* (\S+\.jpg) in Resources \*/ = \{isa = PBXBuildFile; [^\n]*?platformFilters = \((\w+), \);(?: settings = \{ASSET_TAGS = \((\w+), \); \};)? \};')


def check_project_resources(definition_path):
    """The pack's files in the app target as the platforms receive them: iOS's in its tag, the Mac's in the bundle."""
    text = open(os.path.join(REPOSITORY_ROOT, definition_path), encoding="utf-8").read()
    tag = re.search(r'static let onDemandResourcesTag = "(\w+)"', text).group(1)
    project = open(os.path.join(REPOSITORY_ROOT, PROJECT_PATH), encoding="utf-8").read()
    in_project = {name: (platform, file_tag) for name, platform, file_tag in BUILD_FILE_PATTERN.findall(project)}
    touch_section, mac_section = text.split("private static let macFiles", 1)
    expected = {name: ("ios", tag) for name, _, _ in FILE_PATTERN.findall(touch_section)}
    expected.update({name: ("macos", "") for name, _, _ in FILE_PATTERN.findall(mac_section)})
    problems = [f"{name} is in the project as {in_project.get(name)}, not as {platform} {tag_name or 'in the bundle'}"
                for name, (platform, tag_name) in sorted(expected.items()) if in_project.get(name) != (platform, tag_name)]
    problems += [f"{name} is a resource of the project but not a file of the pack" for name in sorted(set(in_project) - set(expected))]
    if not re.search(r"knownAssetTags = \(\s*" + tag + r",\s*\);", project):
        problems.append(f"the project does not know the tag {tag}")
    if project.count(f'"ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS[sdk=iphone*]" = {tag};') != 2:
        problems.append(f"{tag} is not an initial install tag of the app target's Debug and Release configurations")
    print(f"{PROJECT_PATH}: {len(expected)} files of the pack as resources, tag {tag}, {len(problems)} problems")
    return problems


def check(definition_path):
    text = open(os.path.join(REPOSITORY_ROOT, definition_path), encoding="utf-8").read()
    revision = re.search(r'static let revision = "([0-9a-f]{40})"', text).group(1)
    folder = re.search(r'/\\\(revision\)/([^"]+)"\)', text).group(1)
    problems = []
    files = FILE_PATTERN.findall(text)
    for name, byte_count, sha256 in files:
        path = f"{folder}/{name}"
        result = subprocess.run(["git", "-C", REPOSITORY_ROOT, "show", f"{revision}:{path}"], capture_output=True)
        if result.returncode != 0:
            problems.append(f"{path} is not in {revision[:10]}")
            continue
        if len(result.stdout) != int(byte_count) or hashlib.sha256(result.stdout).hexdigest() != sha256:
            problems.append(f"{path} at {revision[:10]} does not match its size or SHA-256")
    print(f"{definition_path}: {len(files)} files at {revision[:10]}, {len(problems)} problems")
    return problems


def main():
    problems = [problem for path in PACK_DEFINITIONS for problem in check(path)]
    problems += check_project_resources(PACK_DEFINITIONS[0])
    for problem in problems:
        print("  " + problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
