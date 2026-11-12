#!/usr/bin/env python3
"""Make the generated files of the release test vault, Tests/ReleaseVault (Docs/Release-test-vault-todo.md).

The vault's notes are written by hand; this script makes the files that are better made than written, so they can be
made again the same way: the pictures (small PNGs and an SVG), the PDFs (a lecture with an outline, a scanned page with
no text layer, a handout annotated with ink, highlights, underlines, strikeouts and text boxes, as another app saves
them), the daily notes of two months, the long lecture note, and the bases copied from Tests/BaseSampleVault. Nothing in
it comes from a person's notes, and it writes no audio or video.

Two files are made by Graphite's own code rather than here: the drawing (a PNG carrying Pencil strokes) and the notebook
(a PDF from the New Notebook sheet's writer). With --graphite-files <swift build folder> the script also runs the gated
package test that writes them (`ReleaseVaultGraphiteFilesTests`, with GRAPHITE_RELEASE_VAULT_FOLDER), building the tests
in that folder, which must be outside iCloud.

The output is the same on every run: no date, random number or time stamp depends on when it runs.

Usage:
  python3 scripts/make-release-vault.py
  python3 scripts/make-release-vault.py --graphite-files /tmp/graphite-build
"""
import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import zlib
from datetime import date, timedelta

REPOSITORY_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VAULT_ROOT = os.path.join(REPOSITORY_ROOT, "Tests", "ReleaseVault")
BASE_SAMPLE_VAULT = os.path.join(REPOSITORY_ROOT, "Tests", "BaseSampleVault")
SYNTHETIC_NOTEBOOKS = os.path.join(REPOSITORY_ROOT, "Tests", "SyntheticNotebooks")
# The notebooks without a recording: an imported recording would be an audio file in the vault.
COPIED_NOTEBOOKS = ["Synthetic text boxes.goodnotes", "Synthetic typed note.note"]


# Pictures ---------------------------------------------------------------------------------------------------------------

def png_chunk(chunk_type, payload):
    return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", zlib.crc32(chunk_type + payload) & 0xFFFFFFFF)


def png_data(width, height, color_at):
    """An 8-bit RGB PNG whose pixel (column, row) is `color_at(column, row)`, a (red, green, blue) triple."""
    rows = bytearray()
    for row in range(height):
        rows.append(0)
        for column in range(width):
            rows.extend(color_at(column, row))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + png_chunk(b"IEND", b""))


def mix(first_color, second_color, fraction):
    return tuple(int(first + (second - first) * fraction) for first, second in zip(first_color, second_color))


def sunset_over_hills(column, row):
    width, height = 480, 270
    first_hill = 190 + 25 * ((column - 160) / 160) ** 2 if column < 320 else 210
    second_hill = 215 - 30 * (1 - ((column - 380) / 200) ** 2)
    if row > first_hill and row > second_hill - 10:
        return (46, 74, 52)
    if row > second_hill:
        return (70, 104, 70)
    sun_distance = ((column - 330) ** 2 + (row - 150) ** 2) ** 0.5
    if sun_distance < 34:
        return (255, 214, 120)
    return mix((40, 60, 140), (250, 150, 90), row / height)


def circuit_sketch(column, row):
    on_wire = (row in (60, 61, 140, 141) and 20 <= column <= 300) or (column in (160, 161) and 60 <= row <= 140)
    in_resistor = 90 <= column <= 130 and 52 <= row <= 69
    in_capacitor = (column in (226, 227, 236, 237)) and 124 <= row <= 158
    on_resistor_border = in_resistor and (column in (90, 130) or row in (52, 69))
    if on_wire and not in_resistor and not (228 <= column <= 235 and 124 <= row <= 158):
        return (20, 20, 20)
    if on_resistor_border or in_capacitor:
        return (20, 20, 20)
    return (250, 250, 247)


def bar_chart(column, row):
    heights = [120, 180, 90, 200, 150]
    for bar_number, bar_height in enumerate(heights):
        left = 30 + bar_number * 64
        if left <= column < left + 44 and 230 - bar_height <= row < 230:
            return mix((70, 120, 220), (230, 110, 60), bar_number / (len(heights) - 1))
    if row == 230 or column == 20:
        return (60, 60, 60)
    return (255, 255, 255)


def portrait_tile(column, row):
    for center_x, center_y, radius, color in [(90, 80, 40, (240, 200, 80)), (60, 180, 30, (90, 170, 200)), (130, 220, 25, (200, 90, 140))]:
        if (column - center_x) ** 2 + (row - center_y) ** 2 < radius ** 2:
            return color
    return mix((235, 240, 250), (150, 160, 200), row / 270)


def square_badge(column, row):
    distance = ((column - 64) ** 2 + (row - 64) ** 2) ** 0.5
    ring = int(distance // 12)
    return [(30, 30, 60), (250, 250, 250), (220, 60, 60), (250, 250, 250), (60, 120, 220), (255, 255, 255)][min(ring, 5)]


def wide_banner(column, row):
    stripe = (column + row * 2) // 40 % 3
    return [(32, 96, 160), (48, 144, 200), (220, 236, 248)][stripe]


def pasted_screenshot(column, row):
    if row < 24:
        return (225, 228, 232)
    if 40 <= row < 52 and 16 <= column < 200 or 64 <= row < 76 and 16 <= column < 160 or 88 <= row < 100 and 16 <= column < 180:
        return (120, 124, 130)
    if 116 <= row < 148 and 16 <= column < 90:
        return (0, 122, 255)
    return (255, 255, 255)


def unicode_name_picture(column, row):
    return (250, 230, 200) if (column // 12 + row // 12) % 2 else (200, 120, 60)


PICTURES = {
    "Attachments/Sunset over hills.png": (480, 270, sunset_over_hills),
    "Attachments/Circuit sketch.png": (320, 200, circuit_sketch),
    "Attachments/Bar chart.png": (360, 240, bar_chart),
    "Attachments/Portrait tile.png": (180, 270, portrait_tile),
    "Attachments/Square badge.png": (128, 128, square_badge),
    "Attachments/Wide banner.png": (900, 120, wide_banner),
    "Attachments/Pasted image 20261001093000.png": (240, 160, pasted_screenshot),
    "Attachments/Café menu – été.png": (96, 96, unicode_name_picture),
}

class LittleEndianBits:
    """Bits written from the lowest of each byte up, as WebP's lossless format reads them."""

    def __init__(self):
        self.bits = []

    def write(self, value, count):
        self.bits.extend((value >> position) & 1 for position in range(count))

    def data(self):
        return bytes(sum(bit << position for position, bit in enumerate(self.bits[start:start + 8])) for start in range(0, len(self.bits), 8))


def write_simple_prefix_code(bits, symbols):
    """A WebP lossless "simple" prefix code of one or two symbols, the second written in eight bits."""
    bits.write(1, 1)
    bits.write(len(symbols) - 1, 1)
    first_symbol = symbols[0]
    if first_symbol < 2:
        bits.write(0, 1)
        bits.write(first_symbol, 1)
    else:
        bits.write(1, 1)
        bits.write(first_symbol, 8)
    if len(symbols) == 2:
        bits.write(symbols[1], 8)


def webp_checkers(side, square, red, green_values, blue):
    """A lossless WebP of two colours in squares, written by hand since Python's standard library has no encoder: no
    transform and no colour cache, a two-symbol code for green (one bit a pixel) and one-symbol codes for red, blue,
    alpha and distance, which take no bits."""
    bits = LittleEndianBits()
    bits.write(0x2F, 8)
    bits.write(side - 1, 14)
    bits.write(side - 1, 14)
    bits.write(0, 1)
    bits.write(0, 3)
    for _ in range(3):
        bits.write(0, 1)  # no transform, no colour cache, no meta prefix codes
    low_green, high_green = sorted(green_values)
    for symbols in ([low_green, high_green], [red], [blue], [255], [0]):
        write_simple_prefix_code(bits, symbols)
    for row in range(side):
        for column in range(side):
            bits.write((column // square + row // square) % 2, 1)
    payload = bits.data()
    chunk = b"VP8L" + struct.pack("<I", len(payload)) + payload + (b"\0" if len(payload) % 2 else b"")
    return b"RIFF" + struct.pack("<I", 4 + len(chunk)) + b"WEBP" + chunk


LOGO_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160">
  <rect x="8" y="8" width="144" height="144" rx="28" fill="#2f3b52"/>
  <path d="M48 112 L80 40 L112 112 Z" fill="none" stroke="#f5c542" stroke-width="10" stroke-linejoin="round"/>
  <circle cx="80" cy="92" r="10" fill="#f5c542"/>
</svg>
"""


# PDFs -------------------------------------------------------------------------------------------------------------------

class PortableDocument:
    """A small PDF writer: numbered objects, written with a cross-reference table, so any PDF reader opens the file."""

    def __init__(self):
        self.objects = []

    def add(self, body):
        """Adds an object (bytes or text) and returns its number."""
        self.objects.append(body.encode("latin-1") if isinstance(body, str) else body)
        return len(self.objects)

    def reserve(self):
        self.objects.append(b"")
        return len(self.objects)

    def replace(self, number, body):
        self.objects[number - 1] = body.encode("latin-1") if isinstance(body, str) else body

    def add_stream(self, dictionary, content, compress=True):
        payload = zlib.compress(content, 9) if compress else content
        filter_entry = " /Filter /FlateDecode" if compress else ""
        return self.add(b"<< " + dictionary.encode("latin-1") + f"{filter_entry} /Length {len(payload)} >>\nstream\n".encode("latin-1")
                        + payload + b"\nendstream")

    def data(self, root_number, info_number):
        output = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
        offsets = []
        for number, body in enumerate(self.objects, start=1):
            offsets.append(len(output))
            output.extend(f"{number} 0 obj\n".encode("latin-1") + body + b"\nendobj\n")
        cross_reference_start = len(output)
        output.extend(f"xref\n0 {len(self.objects) + 1}\n0000000000 65535 f \n".encode("latin-1"))
        for offset in offsets:
            output.extend(f"{offset:010d} 00000 n \n".encode("latin-1"))
        output.extend(f"trailer\n<< /Size {len(self.objects) + 1} /Root {root_number} 0 R /Info {info_number} 0 R >>\n".encode("latin-1"))
        output.extend(f"startxref\n{cross_reference_start}\n%%EOF\n".encode("latin-1"))
        return bytes(output)


def pdf_text(text):
    return "(" + text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ")"


def text_page_content(lines):
    """Content drawing (font size, x, y, text) lines in Helvetica."""
    commands = ["BT"]
    for size, x_position, y_position, text in lines:
        commands.append(f"/F1 {size} Tf 1 0 0 1 {x_position} {y_position} Tm {pdf_text(text)} Tj")
    commands.append("ET")
    return "\n".join(commands).encode("latin-1")


def info_object(document, title):
    # A fixed creation date keeps every run's output the same.
    return document.add(f"<< /Title {pdf_text(title)} /Producer (Graphite release vault script) /CreationDate (D:20261112000000Z) >>")


def write_pdf(path, title, pages, outline_titles=None, annotations_by_page=None, page_extras=None):
    """`pages` is a list of (width, height, content bytes, extra resources); annotations are (dictionary, appearance) pairs;
    `page_extras` adds entries to a page's dictionary, by page index (a /Rotate, a /CropBox)."""
    document = PortableDocument()
    font = document.add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    catalog = document.reserve()
    page_tree = document.reserve()
    page_numbers = []
    for page_index, (width, height, content, extra_resources) in enumerate(pages):
        content_number = document.add_stream("", content)
        page_number = document.reserve()
        annotation_numbers = []
        for annotation, appearance in (annotations_by_page or {}).get(page_index, []):
            appearance_number = None
            if appearance is not None:
                bounding_box, appearance_content, appearance_resources = appearance
                appearance_number = document.add_stream(f"/Type /XObject /Subtype /Form /BBox [{bounding_box}] /Resources << {appearance_resources} >>",
                                                        appearance_content)
            appearance_entry = f" /AP << /N {appearance_number} 0 R >>" if appearance_number else ""
            # A link to another page names it as PAGE<index>: its object is known only once the pages are reserved.
            for target_index, target_number in enumerate(page_numbers):
                annotation = annotation.replace(f"PAGE{target_index}", f"{target_number} 0 R")
            annotation_numbers.append(document.add(f"<< /Type /Annot {annotation} /P {page_number} 0 R{appearance_entry} >>"))
        annotations_entry = f" /Annots [{' '.join(f'{number} 0 R' for number in annotation_numbers)}]" if annotation_numbers else ""
        document.replace(page_number, f"<< /Type /Page /Parent {page_tree} 0 R /MediaBox [0 0 {width} {height}] /Contents {content_number} 0 R"
                                      f" /Resources << /Font << /F1 {font} 0 R >> {extra_resources} >>{annotations_entry}"
                                      f"{(page_extras or {}).get(page_index, '')} >>")
        page_numbers.append(page_number)
    document.replace(page_tree, f"<< /Type /Pages /Kids [{' '.join(f'{number} 0 R' for number in page_numbers)}] /Count {len(page_numbers)} >>")
    outline_entry = ""
    if outline_titles:
        outline_root = document.reserve()
        item_numbers = [document.reserve() for _ in outline_titles]
        for item_index, (item_number, outline_title) in enumerate(zip(item_numbers, outline_titles)):
            neighbours = ""
            if item_index > 0:
                neighbours += f" /Prev {item_numbers[item_index - 1]} 0 R"
            if item_index < len(item_numbers) - 1:
                neighbours += f" /Next {item_numbers[item_index + 1]} 0 R"
            document.replace(item_number, f"<< /Title {pdf_text(outline_title)} /Parent {outline_root} 0 R{neighbours}"
                                          f" /Dest [{page_numbers[item_index]} 0 R /Fit] >>")
        document.replace(outline_root, f"<< /Type /Outlines /First {item_numbers[0]} 0 R /Last {item_numbers[-1]} 0 R /Count {len(item_numbers)} >>")
        outline_entry = f" /Outlines {outline_root} 0 R /PageMode /UseOutlines"
    document.replace(catalog, f"<< /Type /Catalog /Pages {page_tree} 0 R{outline_entry} >>")
    write_file(path, document.data(catalog, info_object(document, title)))


LECTURE_SLIDES = [
    ("Signals and sampling", ["A continuous signal x(t) is sampled every T seconds.", "The sampling rate is f_s = 1 / T.",
                              "Nyquist: f_s must exceed twice the highest frequency.", "Below it, frequencies fold back: aliasing."]),
    ("Quantization", ["Each sample is rounded to one of 2^N levels.", "The step is the full range divided by 2^N.",
                      "Quantization noise is about 6 dB lower per bit.", "Dither spreads the error into broadband noise."]),
    ("The z-transform", ["X(z) is the sum of x[n] z^-n over every n.", "A delay of one sample multiplies by z^-1.",
                         "Poles inside the unit circle mean a stable filter.", "Zeros on the circle remove a frequency."]),
    ("Filters in practice", ["FIR filters are always stable and can have linear phase.", "IIR filters reach a steep edge with fewer taps.",
                             "Windowing trades the main lobe for side lobes.", "Exercise: design a 5-tap moving average."]),
]


def write_lecture_slides():
    pages = []
    for slide_number, (slide_title, bullets) in enumerate(LECTURE_SLIDES, start=1):
        lines = [(30, 60, 520, slide_title)] + [(18, 80, 440 - index * 48, "- " + bullet) for index, bullet in enumerate(bullets)]
        lines.append((10, 700, 30, f"Slide {slide_number}"))
        pages.append((792, 612, text_page_content(lines), ""))
    # The exercise line of the last slide links back to the first, as a PDF's own table of contents links its pages.
    exercise_bottom = 440 - 3 * 48 - 4
    link = (f"/Subtype /Link /Rect [78 {exercise_bottom} 470 {exercise_bottom + 22}] /Border [0 0 0] /Dest [PAGE0 /Fit] /NM (slide-link)", None)
    write_pdf("PDFs/Lecture slides.pdf", "Signals and sampling, lecture 3", pages, outline_titles=[title for title, _ in LECTURE_SLIDES],
              annotations_by_page={3: [link]})


# A 5 by 7 pixel font, enough for the scanned page's words.
GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"], "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"], "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"], "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"], "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"], "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"], "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"], "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"], "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"], "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"], "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"], ",": ["00000", "00000", "00000", "00000", "01100", "00100", "01000"],
    " ": ["00000"] * 7, "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}

SCANNED_LINES = ["LAB SHEET 2", "", "MEASURE THE RISE TIME OF THE", "RC CIRCUIT FOR THREE VALUES", "OF THE RESISTOR.", "",
                 "1. R IS 1 K, C IS 10 N.", "2. R IS 2 K, C IS 10 N.", "3. R IS 5 K, C IS 10 N.", "", "PLOT THE TIME AGAINST R."]


def scanned_page_pixels(width, height):
    """A grey scan of a typed sheet: off-white paper, a shadow along the left edge, the text in the 5 by 7 font, each of
    its dots drawn as a square of `dot_size` pixels."""
    dot_size, left, top, line_height = 3, 50, 90, 36
    pixels = bytearray(236 - max(0, 20 - column) * 2 for _ in range(height) for column in range(width))
    for line_index, text in enumerate(SCANNED_LINES):
        for character_index, character in enumerate(text):
            for glyph_row, bits in enumerate(GLYPHS.get(character, GLYPHS[" "])):
                for glyph_column, bit in enumerate(bits):
                    if bit != "1":
                        continue
                    dot_left = left + (character_index * 6 + glyph_column) * dot_size
                    dot_top = top + line_index * line_height + glyph_row * dot_size
                    for row in range(dot_top, min(dot_top + dot_size, height)):
                        start = row * width + dot_left
                        pixels[start:start + dot_size] = bytes([40]) * dot_size
    return bytes(pixels)


def write_scanned_page():
    width, height = 612, 792
    pixels = scanned_page_pixels(width, height)
    document = PortableDocument()
    image = document.add_stream(f"/Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceGray /BitsPerComponent 8", pixels)
    content = document.add_stream("", f"q {width} 0 0 {height} 0 0 cm /Scan Do Q".encode("latin-1"))
    page_tree = document.reserve()
    page = document.add(f"<< /Type /Page /Parent {page_tree} 0 R /MediaBox [0 0 {width} {height}] /Contents {content} 0 R"
                        f" /Resources << /XObject << /Scan {image} 0 R >> >> >>")
    document.replace(page_tree, f"<< /Type /Pages /Kids [{page} 0 R] /Count 1 >>")
    catalog = document.add(f"<< /Type /Catalog /Pages {page_tree} 0 R >>")
    write_file("PDFs/Scanned page.pdf", document.data(catalog, info_object(document, "Lab sheet 2 (scanned)")))


HANDOUT_PAGES = [
    ["Handout: the RC circuit", "", "A resistor R in series with a capacitor C charges with the", "time constant tau = R C. After one tau the voltage reaches",
     "63 percent of its final value, after five it has settled.", "", "The rise time from 10 to 90 percent is about 2.2 tau.",
     "Doubling R doubles every one of these times.", "", "Questions", "1. What is tau for R = 2 k and C = 10 n?", "2. How long until it settles?"],
    ["Answers", "", "1. tau = 2000 x 10e-9 = 20 microseconds.", "2. About five tau, so 100 microseconds.", "",
     "Check the result on the oscilloscope with a square wave", "whose period is much longer than tau."],
]


def line_box(line_index, text, size=14):
    """The rectangle of a handout line: Helvetica is about half its size wide per character on average."""
    left, baseline = 60, 720 - line_index * 24
    return left, baseline - 4, left + len(text) * size * 0.5, baseline + size


def ink_annotation(points, color):
    xs = [x_position for x_position, _ in points]
    ys = [y_position for _, y_position in points]
    rectangle = f"{min(xs) - 4} {min(ys) - 4} {max(xs) + 4} {max(ys) + 4}"
    ink_list = " ".join(f"{x_position} {y_position}" for x_position, y_position in points)
    path = f"{points[0][0]} {points[0][1]} m " + " ".join(f"{x_position} {y_position} l" for x_position, y_position in points[1:])
    red, green, blue = color
    appearance = (rectangle, f"{red} {green} {blue} RG 2.5 w 1 J 1 j {path} S".encode("latin-1"), "")
    return f"/Subtype /Ink /Rect [{rectangle}] /InkList [[{ink_list}]] /C [{red} {green} {blue}] /BS << /W 2.5 >> /T (Release vault) /NM (ink-{points[0][0]}-{points[0][1]})", appearance


def markup_annotation(subtype, line_index, text, color):
    left, bottom, right, top = line_box(line_index, text)
    quad = f"{left} {top} {right} {top} {left} {bottom} {right} {bottom}"
    red, green, blue = color
    if subtype == "Highlight":
        drawing = f"/G0 gs {red} {green} {blue} rg {left} {bottom} {right - left} {top - bottom} re f"
        resources = "/ExtGState << /G0 << /BM /Multiply /CA 1 /ca 1 >> >>"
    elif subtype == "Underline":
        drawing, resources = f"{red} {green} {blue} RG 1.2 w {left} {bottom + 1} m {right} {bottom + 1} l S", ""
    else:
        middle = (top + bottom) / 2
        drawing, resources = f"{red} {green} {blue} RG 1.2 w {left} {middle} m {right} {middle} l S", ""
    rectangle = f"{left} {bottom} {right} {top}"
    return (f"/Subtype /{subtype} /Rect [{rectangle}] /QuadPoints [{quad}] /C [{red} {green} {blue}] /T (Release vault) /NM ({subtype.lower()}-{line_index})",
            (rectangle, drawing.encode("latin-1"), resources))


def text_box_annotation(rectangle_values, text):
    left, bottom, right, top = rectangle_values
    rectangle = f"{left} {bottom} {right} {top}"
    drawing = (f"1 1 0.85 rg {left} {bottom} {right - left} {top - bottom} re f 0.2 0.2 0.2 RG 0.8 w {left} {bottom} {right - left} {top - bottom} re S"
               f" BT /Helv 11 Tf 0 0 0 rg 1 0 0 1 {left + 6} {top - 16} Tm {pdf_text(text)} Tj ET")
    return (f"/Subtype /FreeText /Rect [{rectangle}] /Contents {pdf_text(text)} /DA (/Helv 11 Tf 0 0 0 rg) /Q 0 /T (Release vault) /NM (text-box-{left})",
            (rectangle, drawing.encode("latin-1"), "/Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>"))


def write_annotated_handout():
    pages = []
    for page_lines in HANDOUT_PAGES:
        lines = [(14, 60, 720 - index * 24, text) for index, text in enumerate(page_lines)]
        lines[0] = (20, 60, 720, page_lines[0])
        pages.append((612, 792, text_page_content(lines), ""))
    first_page = HANDOUT_PAGES[0]
    # A loop around "tau = R C" on the first body line, as a pen circles a word.
    circle = [(round(190 + 42 * math.cos(step / 12 * 2 * math.pi), 1), round(653 + 13 * math.sin(step / 12 * 2 * math.pi), 1)) for step in range(13)]
    arrow = [(420, 520), (360, 560), (372, 548), (360, 560), (376, 562)]
    annotations = {
        0: [markup_annotation("Highlight", 2, first_page[2], (1, 0.9, 0.2)),
            markup_annotation("Underline", 6, first_page[6], (0.1, 0.4, 0.9)),
            markup_annotation("StrikeOut", 7, first_page[7], (0.9, 0.2, 0.2)),
            ink_annotation(circle, (0.85, 0.1, 0.1)),
            ink_annotation(arrow, (0.1, 0.5, 0.2)),
            text_box_annotation((380, 430, 560, 470), "Remember: 2.2 tau")],
        1: [ink_annotation([(80, 560), (95, 575), (110, 560), (125, 575), (140, 560), (155, 575)], (0.2, 0.2, 0.7)),
            text_box_annotation((320, 600, 540, 640), "Checked on 12 November")],
    }
    write_pdf("PDFs/Annotated handout.pdf", "Handout: the RC circuit", pages, annotations_by_page=annotations)


def write_odd_pages():
    """Pages of different sizes and turns, as a PDF stitched from several sources has them: A4 upright, a page turned a
    quarter by its /Rotate, US Letter across, a small card, and a page whose crop box shows only part of its media box."""
    pages = [
        (595, 842, text_page_content([(24, 60, 760, "Page 1: A4, upright"), (14, 60, 720, "The pages of this PDF differ in size and turn.")]), ""),
        (595, 842, text_page_content([(24, 60, 760, "Page 2: turned by /Rotate 90"), (14, 60, 720, "It shows across, read from the side.")]), ""),
        (792, 612, text_page_content([(24, 60, 540, "Page 3: US Letter, across"), (14, 60, 500, "Wider than it is tall.")]), ""),
        (288, 180, text_page_content([(16, 20, 140, "Page 4: a small card"), (10, 20, 110, "Four by two and a half inches.")]), ""),
        (612, 792, text_page_content([(24, 60, 700, "Page 5: cropped"), (14, 60, 660, "Only the middle of the page shows."),
                              (14, 60, 80, "This line is outside the crop box.")]), ""),
    ]
    write_pdf("PDFs/Odd pages.pdf", "Pages of every size and turn", pages,
              page_extras={1: " /Rotate 90", 4: " /CropBox [40 120 572 760]"})


# Notes ------------------------------------------------------------------------------------------------------------------

DAILY_TOPICS = ["sampling", "quantization", "the z-transform", "filters", "the lab report", "the problem set", "the reading group",
                "the oscilloscope lab", "revision", "the mock exam"]


def daily_note_dates():
    """Two months of daily notes, on Mondays and Thursdays from 1 September to 29 October 2026, and today's of the vault."""
    day = date(2026, 9, 1)
    dates = []
    while day <= date(2026, 10, 31):
        if day.weekday() in (0, 3):
            dates.append(day)
        day += timedelta(days=1)
    return dates


def write_daily_notes():
    dates = daily_note_dates()
    for index, day in enumerate(dates):
        topic = DAILY_TOPICS[index % len(DAILY_TOPICS)]
        previous_link = f"Previous: [[{dates[index - 1].isoformat()}]]\n" if index > 0 else ""
        reminder = f"- [ ] Hand in the exercises 📅 {(day + timedelta(days=3)).isoformat()}\n" if index % 3 == 0 else ""
        text = (f"---\ntags:\n  - daily\nmood: {['calm', 'busy', 'tired'][index % 3]}\nstudied: {1 + index % 4}\n---\n"
                f"# {day.strftime('%A %d %B %Y')}\n\n{previous_link}Today: {topic}, after [[Long lecture]].\n\n"
                f"- [x] Read the notes on {topic}\n- [ ] Redo one exercise\n{reminder}\n#daily/{day.strftime('%Y-%m')}\n")
        write_file(f"Daily/{day.isoformat()}.md", text.encode("utf-8"))


def long_lecture_section(section_number):
    lines = [f"## {section_number}. Stage {section_number} of the inverter chain", "",
             f"The **propagation delay** of stage {section_number} is set by its *effective* resistance $R_{{eq}}$ and the load $C_L$ it drives."
             f" Section {section_number} works the chain through with logical effort, $t_p = 0.69\\,R_{{eq}} C_L$.", "",
             f"See [[Math#Display formulas]] and the slides in [[PDF embeds]]. ^stage-{section_number}", "",
             "- Size the first stage for the input capacitance", "- Keep the stage effort near four", "  - the parasitic delay adds $p$",
             f"- Count the stages: $N = \\log_4 F$", "", f"- [ ] Redo exercise {section_number}.a", f"- [x] Read chapter {section_number}", "",
             f"> [!tip] Rule of thumb {section_number}", "> A fanout of four gives a delay close to the optimum.", "",
             "```verilog", f"module inverter_chain_{section_number} (input a, output y);", "  wire [3:0] stage;", "  assign stage[0] = ~a;",
             "  assign y = ~stage[0];", "endmodule", "```", "",
             "| Stage | Size | Delay |", "| --- | ---: | ---: |", f"| {section_number} | {4 ** (section_number % 4)} | 5 ps |",
             f"| {section_number + 1} | {4 ** ((section_number + 1) % 4)} | 5 ps |", "",
             "$$", f"t_{{p,{section_number}}} = 0.69\\, R_{{eq}} \\left( C_{{int}} + C_L \\right)", "$$", ""]
    if section_number % 4 == 0:
        lines += ["![[Circuit sketch.png|320]]", ""]
    return lines


def write_windows_line_endings_note():
    """A note saved by a Windows editor: every line ends with a carriage return and a line feed, which must survive."""
    lines = ["---", "tags:", "  - edge-case", "---", "# Windows line endings", "", "Every line of this note ends with \\r\\n.", "",
             "| Column | Value |", "| --- | --- |", "| a | 1 |", "", "$$", "x^2", "$$", "", "> [!note]", "> A callout.", ""]
    write_file("Edge cases/Windows line endings.md", "\r\n".join(lines).encode("utf-8"))


def write_long_lecture():
    header = ["---", "title: Inverter delay and sizing", "course: Digital circuits", "lecture: 6", "due: 2026-10-07", "reviewed: false",
              "score: 8.5", "tags:", "  - lecture", "  - course/digital-circuits", "aliases:", "  - Inverter sizing lecture", "---", "",
              "# Inverter delay and sizing", "", "A long lecture for scrolling: twelve sections of text, lists, tasks, callouts, code, tables, formulas"
              " and pictures, as a course note has them.", ""]
    body = [line for section_number in range(1, 13) for line in long_lecture_section(section_number)]
    write_file("Lectures/Long lecture.md", "\n".join(header + body).encode("utf-8"))


# Settings (.obsidian) --------------------------------------------------------------------------------------------------

SNIPPET_CSS = """/* Ruled second-level headings and square bullets, to check that CSS snippets apply. */
.markdown-rendered h2, .markdown-source-view h2, .cm-header-2 {
  border-bottom: 1px solid var(--background-modifier-border);
  padding-bottom: 2px;
}
.markdown-rendered ul > li::marker {
  content: "\\25AA  ";
}
"""

THEME_CSS = """/* Release Paper: a small theme of the release test vault, warm headings and a teal accent. */
.theme-light {
  --color-accent: #1b7f79;
  --interactive-accent: #1b7f79;
  --text-accent: #1b7f79;
  --h1-color: #7a3b16;
  --h2-color: #8a4b20;
  --h3-color: #1b5f79;
  --blockquote-border-color: #1b7f79;
  --tag-background: rgba(27, 127, 121, 0.12);
  --tag-color: #14615c;
}
.theme-dark {
  --color-accent: #4fc1b9;
  --interactive-accent: #4fc1b9;
  --text-accent: #4fc1b9;
  --h1-color: #f0b98d;
  --h2-color: #e9a978;
  --h3-color: #8fd0e6;
  --blockquote-border-color: #4fc1b9;
}
"""

TEST_PLUGIN_IDENTIFIER = "release-vault-test"

# A plugin with no network and nothing it plays: a command that inserts a line, and a code block processor that draws a
# counter for `release-vault-count` blocks. Like the hosted tests' own (`CommunityPluginHostTests`), smaller.
TEST_PLUGIN_SOURCE = """'use strict';
const { Plugin, Notice } = require('obsidian');
module.exports = class ReleaseVaultTestPlugin extends Plugin {
    async onload() {
        this.addCommand({
            id: 'insert-checked-line',
            name: 'Insert a checked line',
            editorCallback: (editor) => editor.replaceSelection('Checked by the release vault test plugin.'),
        });
        this.addCommand({ id: 'say-hello', name: 'Say hello', callback: () => new Notice('Hello from the release vault test plugin') });
        this.registerMarkdownCodeBlockProcessor('release-vault-count', (source, element) => {
            let count = Number(source.trim()) || 0;
            const button = element.createEl('button', { cls: 'release-vault-count', text: 'Count ' + count });
            button.addEventListener('click', () => { count += 1; button.setText('Count ' + count); });
        });
    }
};
"""


def json_text(value):
    """JSON as Obsidian writes its settings, `JSON.stringify(value, null, 2)`."""
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def write_obsidian_settings():
    """The settings files Obsidian and Graphite read besides those written by hand: appearance (a theme and a snippet),
    hotkeys, the graph's and the workspace's settings (Obsidian's, which Graphite leaves alone), the calendar's, and the
    community plugin list with the test plugin."""
    write_file(".obsidian/snippets/Ruled headings.css", SNIPPET_CSS.encode("utf-8"))
    write_file(".obsidian/themes/Release Paper/theme.css", THEME_CSS.encode("utf-8"))
    write_file(".obsidian/themes/Release Paper/manifest.json", json_text(
        {"name": "Release Paper", "version": "1.0.0", "minAppVersion": "1.0.0", "author": "Graphite release vault"}))
    write_file(".obsidian/appearance.json", json_text(
        {"accentColor": "#1b7f79", "theme": "system", "cssTheme": "Release Paper", "enabledCssSnippets": ["Ruled headings"],
         "baseFontSize": 16}))
    write_file(".obsidian/hotkeys.json", json_text({
        "editor:toggle-highlight": [{"modifiers": ["Mod", "Shift"], "key": "H"}],
        "graphite:insert-drawing": [{"modifiers": ["Mod", "Alt"], "key": "D"}],
        "workspace:export-pdf": [],
        TEST_PLUGIN_IDENTIFIER + ":insert-checked-line": [{"modifiers": ["Mod", "Shift"], "key": "L"}],
    }))
    write_file(".obsidian/graph.json", json_text({
        "collapse-filter": False, "search": "", "showTags": True, "showAttachments": False, "hideUnresolved": False, "showOrphans": True,
        "collapse-color-groups": False,
        "colorGroups": [{"query": "path:Daily", "color": {"a": 1, "rgb": 1482617}}, {"query": "tag:#book", "color": {"a": 1, "rgb": 14701138}}],
        "collapse-display": False, "showArrow": True, "textFadeMultiplier": 0, "nodeSizeMultiplier": 1.2, "lineSizeMultiplier": 1,
        "collapse-forces": True, "centerStrength": 0.5, "repelStrength": 10, "linkStrength": 1, "linkDistance": 250, "scale": 1, "close": True,
    }))
    write_file(".obsidian/workspace.json", json_text({
        "main": {"id": "release-main", "type": "split", "direction": "vertical", "children": [
            {"id": "release-tabs", "type": "tabs", "children": [
                {"id": "release-leaf", "type": "leaf", "state": {"type": "markdown", "state": {"file": "Start here.md", "mode": "source"}}}]}]},
        "active": "release-leaf",
        "lastOpenFiles": ["Start here.md", "Embeds/Pictures in every form.md", "PDFs/Written in Graphite.pdf"],
    }))
    write_file(".obsidian/graphite-calendar.json", json_text(
        {"eventNoteFolders": {"Lectures": "Lectures"}, "defaultEventNoteFolder": "Daily", "taskList": "Release vault", "importedList": ""}))
    write_file(".obsidian/community-plugins.json", json_text([TEST_PLUGIN_IDENTIFIER]))
    plugin_folder = f".obsidian/plugins/{TEST_PLUGIN_IDENTIFIER}"
    write_file(f"{plugin_folder}/manifest.json", json_text(
        {"id": TEST_PLUGIN_IDENTIFIER, "name": "Release Vault Test", "version": "1.0.0", "minAppVersion": "1.0.0",
         "description": "A command and a code block, to try community plugins without the network.", "author": "Graphite release vault",
         "isDesktopOnly": False}))
    write_file(f"{plugin_folder}/main.js", TEST_PLUGIN_SOURCE.encode("utf-8"))


# Copies and output -----------------------------------------------------------------------------------------------------

def copy_bases():
    """The bases and the notes they show, from Tests/BaseSampleVault: books (table, cards, list), places (map), tasks. They keep
    their places at the vault's root, where their filters (`file.inFolder("Books")`) and the books' covers find them."""
    for folder in ["Books", "Places", "Tasks"]:
        destination = os.path.join(VAULT_ROOT, folder)
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(os.path.join(BASE_SAMPLE_VAULT, folder), destination)
    for name in ["Books.base", "Places.base", "Tasks.base", "Places.md"]:
        shutil.copyfile(os.path.join(BASE_SAMPLE_VAULT, name), os.path.join(VAULT_ROOT, name))


def copy_notebooks():
    for name in COPIED_NOTEBOOKS:
        shutil.copyfile(os.path.join(SYNTHETIC_NOTEBOOKS, name), os.path.join(VAULT_ROOT, "Notebooks", name))


def write_file(relative_path, contents):
    location = os.path.join(VAULT_ROOT, relative_path)
    os.makedirs(os.path.dirname(location), exist_ok=True)
    with open(location, "wb") as handle:
        handle.write(contents)


def write_graphite_files(build_folder):
    """Runs the gated package test that writes the drawing and the notebook with Graphite's own writers."""
    environment = dict(os.environ, GRAPHITE_RELEASE_VAULT_FOLDER=VAULT_ROOT)
    subprocess.run(["swift", "build", "--build-tests", "--scratch-path", build_folder], cwd=REPOSITORY_ROOT, check=True)
    subprocess.run(["swift", "test", "--skip-build", "--scratch-path", build_folder, "--filter", "ReleaseVaultGraphiteFilesTests"],
                   cwd=REPOSITORY_ROOT, env=environment, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--graphite-files", metavar="BUILD_FOLDER", help="also write the drawing and the notebook, building in this folder")
    arguments = parser.parse_args()
    for relative_path, (width, height, color_at) in PICTURES.items():
        write_file(relative_path, png_data(width, height, color_at))
    write_file("Attachments/Logo.svg", LOGO_SVG.encode("utf-8"))
    write_file("Attachments/Checkers.webp", webp_checkers(96, 12, 30, (60, 200), 140))
    write_lecture_slides()
    write_scanned_page()
    write_annotated_handout()
    write_daily_notes()
    write_long_lecture()
    write_windows_line_endings_note()
    write_odd_pages()
    write_obsidian_settings()
    copy_bases()
    copy_notebooks()
    if arguments.graphite_files:
        write_graphite_files(arguments.graphite_files)
    total_bytes = sum(os.path.getsize(os.path.join(folder, name)) for folder, _, names in os.walk(VAULT_ROOT) for name in names)
    print(f"Tests/ReleaseVault: {total_bytes / 1_048_576:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
