#!/usr/bin/env python3
"""Make the generated files of the Graphite Guide vault, Guide/Graphite Guide (Docs/Guide-vault-todo.md).

The guide's notes are written by hand; this script makes the files that are better made than written, so they can be
made again the same way:

- the pictures of the everyday examples: dishes seen from above for the recipes, book covers for the reading list and a
  banner for the trip, drawn as flat shapes (no photo, no person);
- the covers of the dashboards (`banner`) and the Solar Boat Team's picture icon (`icon`), an SVG;
- the slides of the example course, a PDF with an outline, drawn with the release vault's PDF writer;
- copies of files Graphite's own writers made for the release test vault (Tests/ReleaseVault): a drawing of every Pencil
  tool, a circuit drawing and a Cornell notebook, so they open for editing stroke by stroke;
- the pack list of the guide (`Sources/GraphiteUI/GuideVaultPack.swift`'s file list), with `--pack-revision <commit>`:
  every file's name, size and SHA-256 at that commit, for the in-app Guide's download, and the earlier files: each path
  and SHA-256 that a revision pinned before had and this one does not, so the Guide can tell its own unchanged files in
  a reader's copy from the reader's edits when it brings the copy up to date (Docs/Guide-vault-todo.md, section 7).

The screenshots of the app in `Attachments/Screenshots/` are taken from the simulators and the Mac app, not drawn here.

The output is the same on every run: nothing depends on when it runs.

Usage:
  python3 scripts/make-guide-vault.py
  python3 scripts/make-guide-vault.py --pack-revision <commit on main that holds the vault>
"""
import argparse
import hashlib
import importlib.util
import math
import os
import re
import shutil
import subprocess
import sys

REPOSITORY_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE_FOLDER = "Guide/Graphite Guide"
VAULT_ROOT = os.path.join(REPOSITORY_ROOT, GUIDE_FOLDER)
RELEASE_VAULT = os.path.join(REPOSITORY_ROOT, "Tests", "ReleaseVault")
PACK_DEFINITION = os.path.join(REPOSITORY_ROOT, "Sources", "GraphiteUI", "GuideVaultPack.swift")
MAXIMUM_VAULT_BYTES = 5 * 1_048_576


def load_release_vault_script():
    """The release vault's script, for its PNG and PDF writers, pointed at this vault."""
    specification = importlib.util.spec_from_file_location("make_release_vault", os.path.join(REPOSITORY_ROOT, "scripts", "make-release-vault.py"))
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    module.VAULT_ROOT = VAULT_ROOT
    return module


RELEASE = load_release_vault_script()


def write_file(relative_path, contents):
    location = os.path.join(VAULT_ROOT, relative_path)
    os.makedirs(os.path.dirname(location), exist_ok=True)
    with open(location, "wb") as handle:
        handle.write(contents)


# Flat pictures ----------------------------------------------------------------------------------------------------------

class FlatPicture:
    """Shapes painted in order over a background, each pixel sampled four times so edges are smooth."""

    def __init__(self, width, height, background):
        self.width = width
        self.height = height
        self.background = background
        self.shapes = []

    def ellipse(self, center_x, center_y, radius_x, radius_y, color):
        self.shapes.append((lambda x, y: ((x - center_x) / radius_x) ** 2 + ((y - center_y) / radius_y) ** 2 <= 1, color,
                            (center_x - radius_x, center_y - radius_y, center_x + radius_x, center_y + radius_y)))
        return self

    def circle(self, center_x, center_y, radius, color):
        return self.ellipse(center_x, center_y, radius, radius, color)

    def rectangle(self, left, top, right, bottom, color, corner_radius=0):
        def inside(x, y):
            if not (left <= x <= right and top <= y <= bottom):
                return False
            nearest_x = min(max(x, left + corner_radius), right - corner_radius)
            nearest_y = min(max(y, top + corner_radius), bottom - corner_radius)
            return (x - nearest_x) ** 2 + (y - nearest_y) ** 2 <= corner_radius ** 2
        self.shapes.append((inside, color, (left, top, right, bottom)))
        return self

    def polygon(self, points, color):
        def inside(x, y):
            crossings = False
            for index in range(len(points)):
                (first_x, first_y), (second_x, second_y) = points[index], points[index - 1]
                if (first_y > y) != (second_y > y) and x < (second_x - first_x) * (y - first_y) / (second_y - first_y) + first_x:
                    crossings = not crossings
            return crossings
        xs, ys = [point[0] for point in points], [point[1] for point in points]
        self.shapes.append((inside, color, (min(xs), min(ys), max(xs), max(ys))))
        return self

    def color_at(self, column, row):
        totals = [0, 0, 0]
        for offset_x, offset_y in ((0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)):
            x, y = column + offset_x, row + offset_y
            color = self.background(x, y) if callable(self.background) else self.background
            for inside, shape_color, (left, top, right, bottom) in self.shapes:
                if left <= x <= right and top <= y <= bottom and inside(x, y):
                    color = shape_color
            for channel in range(3):
                totals[channel] += color[channel]
        return tuple(total // 4 for total in totals)

    def png(self):
        return RELEASE.png_data(self.width, self.height, self.color_at)


TABLE = (232, 222, 206)
PLATE = (250, 249, 245)
PLATE_RIM = (226, 223, 214)


def plate(picture, center_x, center_y, radius):
    return picture.circle(center_x, center_y, radius, PLATE_RIM).circle(center_x, center_y, radius * 0.86, PLATE)


def tomato_soup():
    picture = plate(FlatPicture(480, 320, TABLE), 240, 160, 140)
    picture.circle(240, 160, 104, (196, 64, 44)).circle(240, 160, 96, (214, 82, 52))
    for x, y in ((210, 130), (262, 150), (236, 190), (280, 186), (200, 172)):
        picture.ellipse(x, y, 9, 4, (92, 140, 64))
    picture.ellipse(248, 168, 30, 14, (247, 240, 226))
    return picture.rectangle(400, 120, 420, 300, (180, 184, 190), 8).ellipse(410, 110, 22, 30, (180, 184, 190))


def lemon_cake():
    picture = plate(FlatPicture(480, 320, TABLE), 240, 160, 140)
    picture.polygon([(240, 160), (350, 110), (350, 214)], (236, 205, 120))
    picture.polygon([(240, 160), (350, 110), (350, 122), (250, 165)], (250, 246, 230))
    for x, y in ((150, 120), (170, 210), (130, 170)):
        picture.circle(x, y, 26, (246, 214, 64)).circle(x, y, 20, (250, 232, 120))
    return picture.ellipse(318, 150, 8, 5, (110, 160, 80))


def mushroom_risotto():
    picture = plate(FlatPicture(480, 320, TABLE), 240, 160, 140)
    picture.ellipse(240, 160, 100, 92, (238, 226, 190))
    for x, y in ((205, 135), (268, 140), (230, 192), (282, 190), (196, 182), (250, 116)):
        picture.ellipse(x, y, 18, 12, (150, 112, 82)).ellipse(x, y + 4, 7, 9, (214, 196, 170))
    for x, y in ((226, 158), (258, 170), (214, 112), (290, 162)):
        picture.ellipse(x, y, 6, 3, (98, 150, 72))
    return picture


def pancakes():
    picture = plate(FlatPicture(480, 320, TABLE), 240, 160, 140)
    for offset in (14, 7, 0):
        picture.circle(240 - offset, 160 - offset, 96, (204, 146, 76)).circle(240 - offset, 160 - offset, 88, (226, 176, 102))
    picture.ellipse(232, 150, 46, 30, (150, 82, 30))
    for x, y in ((196, 110), (284, 120), (270, 210), (190, 196)):
        picture.circle(x, y, 10, (70, 70, 150))
    return picture.rectangle(214, 136, 246, 160, (250, 236, 170), 4)


def book_cover(base, accent, motif):
    picture = FlatPicture(240, 360, base)
    picture.rectangle(0, 0, 16, 360, tuple(max(channel - 40, 0) for channel in base))
    picture.rectangle(40, 40, 210, 52, accent).rectangle(40, 300, 170, 310, accent)
    if motif == "waves":
        for index in range(4):
            picture.ellipse(125, 150 + index * 28, 80 - index * 10, 10, accent)
    elif motif == "sun":
        picture.circle(125, 170, 56, accent).circle(125, 170, 40, base).circle(125, 170, 24, accent)
    elif motif == "mountain":
        picture.polygon([(40, 250), (110, 120), (180, 250)], accent).polygon([(110, 250), (160, 160), (210, 250)], tuple((channel + 255) // 2 for channel in accent))
    else:
        for row in range(3):
            for column in range(3):
                picture.rectangle(56 + column * 48, 110 + row * 48, 92 + column * 48, 146 + row * 48, accent, 6)
    return picture


def trip_banner():
    def sky(x, y):
        return RELEASE.mix((126, 186, 230), (252, 222, 178), y / 260)
    picture = FlatPicture(900, 260, sky)
    picture.circle(720, 70, 40, (255, 236, 160))
    picture.polygon([(0, 260), (0, 170), (180, 120), (380, 180), (560, 130), (760, 170), (900, 140), (900, 260)], (218, 160, 120))
    for index, (left, height, color) in enumerate(((60, 70, (240, 214, 170)), (140, 90, (236, 236, 228)), (230, 60, (246, 196, 120)),
                                                    (420, 80, (240, 220, 200)), (500, 64, (230, 232, 236)), (640, 96, (248, 214, 150)))):
        top = 260 - height
        picture.rectangle(left, top, left + 70, 260, color).polygon([(left - 6, top), (left + 35, top - 26), (left + 76, top)], (196, 92, 62))
        for window in range(2):
            picture.rectangle(left + 12 + window * 30, top + 18, left + 26 + window * 30, top + 36, (90, 120, 160))
    picture.rectangle(300, 214, 400, 250, (246, 204, 64), 8).rectangle(312, 222, 332, 236, (120, 160, 200)).rectangle(344, 222, 364, 236, (120, 160, 200))
    return picture.circle(320, 252, 6, (60, 60, 60)).circle(380, 252, 6, (60, 60, 60))


# The dashboards' covers: wide, so the reading view can crop them to any window, and mostly flat, so they stay small.

COVER_WIDTH, COVER_HEIGHT = 1200, 300


def left_to_right(colors):
    """A background that runs through `colors` from the left edge to the right one."""
    def background(x, y):
        position = min(max(x / COVER_WIDTH, 0), 1) * (len(colors) - 1)
        index = min(int(position), len(colors) - 2)
        return RELEASE.mix(colors[index], colors[index + 1], position - index)
    return background


def wave(picture, middle, amplitude, wavelength, half_thickness, color, phase=0.0):
    """A sine curve drawn as a band across the whole picture."""
    def inside(x, y):
        return abs(y - (middle + amplitude * math.sin(2 * math.pi * x / wavelength + phase))) <= half_thickness
    picture.shapes.append((inside, color, (0, middle - amplitude - half_thickness, picture.width, middle + amplitude + half_thickness)))
    return picture


def signals_cover():
    picture = FlatPicture(COVER_WIDTH, COVER_HEIGHT, left_to_right([(36, 52, 112), (98, 62, 140), (214, 96, 104)]))
    wave(picture, 150, 46, 300, 5, (236, 226, 250))
    wave(picture, 150, 22, 150, 3, (180, 168, 222), phase=1.3)
    for index in range(9):
        picture.circle(90 + index * 128, 236, 6, (236, 226, 250))
    return picture


def solar_boat_cover():
    picture = FlatPicture(COVER_WIDTH, COVER_HEIGHT, left_to_right([(250, 206, 150), (150, 196, 222), (70, 128, 186)]))
    picture.circle(250, 118, 54, (255, 238, 176))
    picture.rectangle(0, 214, COVER_WIDTH, COVER_HEIGHT, (40, 96, 150))
    wave(picture, 214, 6, 120, 5, (40, 96, 150))
    wave(picture, 256, 5, 160, 3, (90, 150, 196), phase=0.8)
    picture.polygon([(620, 196), (840, 196), (812, 222), (648, 222)], (246, 246, 242))
    picture.rectangle(668, 168, 792, 196, (30, 46, 80), 4)
    for panel in range(4):
        picture.rectangle(674 + panel * 30, 172, 700 + panel * 30, 192, (64, 112, 190), 2)
    return picture


def balcony_garden_cover():
    picture = FlatPicture(COVER_WIDTH, COVER_HEIGHT, left_to_right([(246, 236, 214), (214, 232, 196), (150, 196, 150)]))
    picture.rectangle(0, 250, COVER_WIDTH, COVER_HEIGHT, (196, 176, 150))
    for left, leaf_color, fruit_color in ((180, (84, 146, 84), (220, 70, 56)), (520, (64, 128, 76), None), (860, (96, 156, 92), (236, 186, 60))):
        for offset_x, offset_y in ((-30, -10), (30, -10), (0, -44), (-24, -74), (24, -74)):
            picture.ellipse(left + 60 + offset_x, 170 + offset_y, 26, 16, leaf_color)
        if fruit_color:
            picture.circle(left + 40, 186, 11, fruit_color).circle(left + 84, 150, 10, fruit_color)
        picture.polygon([(left, 206), (left + 120, 206), (left + 106, 266), (left + 14, 266)], (196, 108, 72))
        picture.rectangle(left - 6, 198, left + 126, 212, (176, 92, 60), 3)
    return picture


SOLAR_BOAT_ICON = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <circle cx="44" cy="18" r="10" fill="#f5b83d"/>
  <rect x="14" y="26" width="30" height="10" rx="2" fill="#24406e"/>
  <rect x="17" y="28" width="7" height="6" fill="#4f86d0"/>
  <rect x="26" y="28" width="7" height="6" fill="#4f86d0"/>
  <rect x="35" y="28" width="7" height="6" fill="#4f86d0"/>
  <polygon points="6,38 58,38 50,48 14,48" fill="#e8eef4" stroke="#24406e" stroke-width="2"/>
  <path d="M4 54 Q 12 50 20 54 T 36 54 T 52 54 T 60 54" fill="none" stroke="#3a7dc0" stroke-width="3" stroke-linecap="round"/>
</svg>
"""


PICTURES = {
    "Attachments/Tomato soup.png": tomato_soup,
    "Attachments/Lemon cake.png": lemon_cake,
    "Attachments/Mushroom risotto.png": mushroom_risotto,
    "Attachments/Pancakes.png": pancakes,
    "Attachments/Cover - The Quiet Harbour.png": lambda: book_cover((38, 70, 110), (230, 214, 170), "waves"),
    "Attachments/Cover - A Year of Bread.png": lambda: book_cover((196, 120, 60), (252, 240, 214), "sun"),
    "Attachments/Cover - Maps of Small Places.png": lambda: book_cover((54, 110, 84), (232, 236, 220), "mountain"),
    "Attachments/Cover - The Patient Gardener.png": lambda: book_cover((120, 60, 96), (246, 214, 230), "squares"),
    "Attachments/Lisbon weekend.png": trip_banner,
    "Attachments/Cover - Signals and Sound.png": signals_cover,
    "Attachments/Cover - Solar Boat Team.png": solar_boat_cover,
    "Attachments/Cover - Balcony Garden.png": balcony_garden_cover,
}


# The course's slides ----------------------------------------------------------------------------------------------------

COURSE_SLIDES = [
    ("Everyday Electronics, week 1", ["Voltage pushes, current flows, resistance holds back.", "Ohm's law: V = I x R.",
                                      "Power is what you pay for: P = V x I.", "Today: a torch, a phone charger, a kettle."]),
    ("Voltage, current, resistance", ["Voltage is measured in volts (V).", "Current is measured in amperes (A).",
                                      "Resistance is measured in ohms.", "Double the voltage, double the current."]),
    ("Series and parallel", ["In series, resistances add up.", "In parallel, the current takes every path.",
                             "Lamps in a house are in parallel.", "One broken bulb leaves the others on."]),
    ("Capacitors", ["A capacitor stores charge between two plates.", "It is measured in farads (F).",
                    "With a resistor it fills in about R x C seconds.", "That is the RC time constant."]),
    ("Exercise", ["A kettle draws 8.7 A from 230 V.", "What is its power?", "How long to use 1 kWh?",
                  "Bring your answer to week 2."]),
]


def write_course_slides():
    pages = []
    for slide_number, (slide_title, bullets) in enumerate(COURSE_SLIDES, start=1):
        lines = [(30, 60, 520, slide_title)] + [(20, 80, 430 - index * 52, "- " + bullet) for index, bullet in enumerate(bullets)]
        lines.append((10, 690, 30, f"Everyday Electronics - slide {slide_number}"))
        pages.append((792, 612, RELEASE.text_page_content(lines), ""))
    RELEASE.write_pdf("6 Everyday examples/Everyday Electronics/Week 1 slides.pdf", "Everyday Electronics, week 1", pages,
                      outline_titles=[title for title, _ in COURSE_SLIDES])


# Files made by Graphite's own writers ----------------------------------------------------------------------------------

COPIED_FROM_RELEASE_VAULT = {
    "Drawings/Every tool.png": "Attachments/Every Pencil tool.png",
    "Drawings/Circuit drawing.png": "Attachments/Circuit drawing.png",
    "Notebooks/Papers/Cornell.pdf": "6 Everyday examples/Everyday Electronics/Week 1 notebook.pdf",
}


def copy_graphite_files():
    for source, destination in COPIED_FROM_RELEASE_VAULT.items():
        location = os.path.join(VAULT_ROOT, destination)
        os.makedirs(os.path.dirname(location), exist_ok=True)
        shutil.copyfile(os.path.join(RELEASE_VAULT, source), location)


# The pack list ----------------------------------------------------------------------------------------------------------

def vault_files_at(revision):
    """Every file of the guide vault at `revision`, hidden settings included, with its bytes."""
    listing = subprocess.run(["git", "-C", REPOSITORY_ROOT, "ls-tree", "-r", "-z", "--name-only", revision, "--", GUIDE_FOLDER],
                             capture_output=True, check=True).stdout.decode("utf-8").split("\0")
    files = []
    for path in sorted(path for path in listing if path):
        contents = subprocess.run(["git", "-C", REPOSITORY_ROOT, "show", f"{revision}:{path}"], capture_output=True, check=True).stdout
        files.append((path[len(GUIDE_FOLDER) + 1:], contents))
    return files


def pinned_revisions():
    """Every revision the pack list was pinned at in the history of the checkout, the one written now included."""
    history = subprocess.run(["git", "-C", REPOSITORY_ROOT, "log", "--format=", "-p", "--", os.path.relpath(PACK_DEFINITION, REPOSITORY_ROOT)],
                             capture_output=True, check=True, text=True).stdout
    current = open(PACK_DEFINITION, encoding="utf-8").read()
    return set(re.findall(r'static let revision = "([0-9a-f]{40})"', history + current))


def earlier_files(revision, current_files):
    """(name, contents) of each path and version that an earlier pinned revision had and `revision` does not."""
    current = {(name, hashlib.sha256(contents).hexdigest()) for name, contents in current_files}
    earlier = {}
    for earlier_revision in sorted(pinned_revisions() - {revision}):
        resolves = subprocess.run(["git", "-C", REPOSITORY_ROOT, "cat-file", "-e", earlier_revision + "^{commit}"], capture_output=True).returncode == 0
        if not resolves:
            continue
        for name, contents in vault_files_at(earlier_revision):
            key = (name, hashlib.sha256(contents).hexdigest())
            if key not in current:
                earlier[key] = contents
    return sorted((name, contents) for (name, _), contents in earlier.items())


def pack_lines(files):
    return [f'        AddOnFile(name: "{name}", byteCount: {len(contents)},\n                  sha256: "{hashlib.sha256(contents).hexdigest()}"),'
            for name, contents in files]


def write_pack_list(revision):
    files = vault_files_at(revision)
    earlier = earlier_files(revision, files)
    definition = open(PACK_DEFINITION, encoding="utf-8").read()
    definition = re.sub(r'static let revision = "[0-9a-f]{40}"', f'static let revision = "{revision}"', definition)
    for list_name, entries in (("files", files), ("earlierFiles", earlier)):
        definition = re.sub(rf"(static let {list_name}: \[AddOnFile\] = \[\n)(?:.*?\n)?(    \])",
                            lambda match: match.group(1) + "".join(line + "\n" for line in pack_lines(entries)) + match.group(2),
                            definition, count=1, flags=re.DOTALL)
    with open(PACK_DEFINITION, "w", encoding="utf-8") as handle:
        handle.write(definition)
    print(f"{os.path.relpath(PACK_DEFINITION, REPOSITORY_ROOT)}: {len(files)} files at {revision[:10]}, {sum(len(contents) for _, contents in files) / 1_048_576:.2f} MB,"
          f" {len(earlier)} earlier versions")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pack-revision", metavar="COMMIT", help="write the pack list of the vault as it is at this commit, and nothing else")
    arguments = parser.parse_args()
    if arguments.pack_revision:
        revision = subprocess.run(["git", "-C", REPOSITORY_ROOT, "rev-parse", arguments.pack_revision], capture_output=True, check=True,
                                  text=True).stdout.strip()
        write_pack_list(revision)
        return 0
    for relative_path, make_picture in PICTURES.items():
        write_file(relative_path, make_picture().png())
    write_file("Attachments/Solar boat.svg", SOLAR_BOAT_ICON.encode("utf-8"))
    write_course_slides()
    copy_graphite_files()
    total_bytes = sum(os.path.getsize(os.path.join(folder, name)) for folder, _, names in os.walk(VAULT_ROOT) for name in names)
    print(f"{GUIDE_FOLDER}: {total_bytes / 1_048_576:.2f} MB")
    return 0 if total_bytes < MAXIMUM_VAULT_BYTES else 1


if __name__ == "__main__":
    sys.exit(main())
