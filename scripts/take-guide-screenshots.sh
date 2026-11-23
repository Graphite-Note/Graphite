#!/bin/zsh
# Take the pictures of the app that the Graphite Guide vault shows (Docs/Guide-vault-todo.md, section 2), in an iPad or
# iPhone simulator, from the guide vault itself.
#
# The simulator gets a copy of Guide/Graphite Guide as its only vault. For each picture the app is quit, told which file
# to open at launch (the vault's last opened document, with no tabs remembered) and in which view and appearance, then
# launched and photographed. The pictures are written as small JPEGs into the vault's Attachments/Screenshots folder.
# A shot can also say, in a fifth field of `;`-separated options: `top=<line>` opens the note with that line of it at the
# top (its remembered place), `split=right:<file>` or `split=down:<file>` shows a second file on the other side of a
# split (the shot's file left or above), `snippet=<name>` turns on the vault's theme with that CSS snippet, and
# `crop=<from>:<to>` keeps only that part of the picture's height, as fractions from the top.
#
# The simulator must be one of your own (never another session's), with Graphite built for it. Nothing in the guide
# plays a sound, keyboard clicks are turned off, and the simulator is shut down at the end.
#
# Usage:
#   scripts/take-guide-screenshots.sh <simulator UDID> <path to the built Graphite.app> <iPad|iPhone> [shot name…]
# With shot names, only those are taken again.

set -e
setopt null_glob

device="$1"; app="$2"; family="$3"; shift 3
only=("$@")
repository="${0:A:h:h}"
vault_source="$repository/Guide/Graphite Guide"
output="$vault_source/Attachments/Screenshots"
bundle="com.graphite.study"
vault_name="Graphite Guide"
vault_identifier="6B1E7C2A-2F4D-4C51-9E0A-6C0F5D7A1B11"
width=$([[ "$family" == "iPhone" ]] && print 640 || print 1200)
mkdir -p "$output"

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl spawn "$device" defaults write com.apple.Preferences KeyboardClicks -bool false
xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" "$bundle" >/dev/null; sleep 3; xcrun simctl terminate "$device" "$bundle" || true
container="$(xcrun simctl get_app_container "$device" "$bundle" data)"
rm -rf "$container/Documents/$vault_name"
cp -R "$vault_source" "$container/Documents/$vault_name"
rm -rf "$container/Documents/$vault_name/Attachments/Screenshots"
# A checkout below .claude on the iCloud Desktop marks every file hidden, which Graphite would leave out.
chflags -R nohidden "$container/Documents/$vault_name"
preferences="$container/Library/Preferences/$bundle"

# shot name, file in the vault, view (reading or editing), appearance (light or dark)
shots=(
  "Start here|Start here.md|reading|light"
  "A drawing in a note|6 Everyday examples/Everyday Electronics/Week 2 - Capacitors.md|reading|light"
  "A slide in a lecture note|6 Everyday examples/Everyday Electronics/Week 1 - Voltage and current.md|editing|light"
  "Callouts|4 Making notes look good/Quotes and callouts.md|reading|dark"
  "Math|4 Making notes look good/Math.md|reading|light"
  "Diagrams|4 Making notes look good/Diagrams.md|reading|dark"
  "Tables|4 Making notes look good/Tables.md|editing|light"
  "Recipes gallery|6 Everyday examples/Recipes/Recipes.base|reading|light"
  "Restaurants map|6 Everyday examples/Restaurants/Restaurants.base|reading|light"
  "A recipe|6 Everyday examples/Recipes/Tomato soup.md|reading|dark"
  "Reading list|6 Everyday examples/Reading list/Reading list.base|reading|dark"
  "Slides|6 Everyday examples/Everyday Electronics/Week 1 slides.pdf|reading|light"
  "Lisbon weekend|6 Everyday examples/Trip/Lisbon weekend.md|reading|light"
  "Diagram colours|4 Making notes look good/Diagrams.md|reading|light|top=## Your own colours;crop=0:0.68"
  "Diagram colours from a snippet|4 Making notes look good/Diagrams.md|reading|light|top=## A timeline;snippet=Diagram colours;crop=0:0.62"
  "Diagrams in a split, dark|4 Making notes look good/Diagrams.md|reading|dark|top=**What you see**;split=right:6 Everyday examples/Everyday Electronics/Week 1 - Voltage and current.md;crop=0:0.72"
  "A PDF above its note|6 Everyday examples/Everyday Electronics/Week 1 slides.pdf|reading|light|split=down:6 Everyday examples/Everyday Electronics/Week 1 - Voltage and current.md"
)

hex_of() { print -rn -- "$1" | xxd -p | tr -d '\n'; }
appearance_file="$container/Documents/$vault_name/.obsidian/appearance.json"
appearance_original="$(cat "$appearance_file")"

# The value of option `$2` in the options `$1`, or nothing.
option_of() { local pair; for pair in ${(s:;:)1}; do [[ "$pair" == "$2="* ]] && { print -r -- "${pair#$2=}"; return; }; done; return 0; }

# The remembered places of the vault, with the note `$1` shown from the line `$2`, as Graphite writes them.
places_with_top() {
  python3 -I - "$container/Documents/$vault_name/$1" "$1" "$2" <<'PLACES'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
line_start = text.index("\n" + sys.argv[3] + "\n") + 1
offset = len(text[:line_start].encode("utf-16-le")) // 2
place = {"place": {"note": {"_0": {"topLocation": offset, "selectionLocation": 0, "selectionLength": 0}}}, "leftAt": 816480000.0}
print(json.dumps({"placesByPath": {sys.argv[2]: place}}), end="")
PLACES
}

# The tab layout of two sides, `$2` (right or down), the shot's file `$1` left or above and `$3` on the other side.
split_layout() {
  local direction=""
  [[ "$2" == "down" ]] && direction=',"splitDirection":"aboveAndBelow"'
  print -rn -- "{\"groups\":[{\"tabs\":[{\"path\":\"$1\",\"isPinned\":false}],\"activeTabIndex\":0},{\"tabs\":[{\"path\":\"$3\",\"isPinned\":false}],\"activeTabIndex\":0}],\"focusedGroupIndex\":1,\"splitFraction\":0.5$direction}"
}

for shot in "${shots[@]}"; do
  IFS='|' read -r name file view appearance shot_options <<< "$shot"
  if (( ${#only} )) && (( ! ${only[(Ie)$name]} )); then continue; fi
  xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
  vaults="{\"vaults\":[{\"location\":{\"anchor\":{\"applicationDocuments\":{}},\"relativePath\":\"$vault_name\"},\"id\":\"$vault_identifier\",\"name\":\"$vault_name\",\"lastKnownPath\":\"$container/Documents/$vault_name\",\"lastOpenedDate\":816480000.0,\"lastOpenedDocument\":{\"rawValue\":\"$file\"}}]}"
  xcrun simctl spawn "$device" defaults write "$preferences" GraphiteKnownVaults -data "$(hex_of "$vaults")"
  xcrun simctl spawn "$device" defaults delete "$preferences" "GraphiteTabLayout.$vault_identifier" 2>/dev/null || true
  xcrun simctl spawn "$device" defaults delete "$preferences" "GraphiteNoteViews.$vault_identifier" 2>/dev/null || true
  xcrun simctl spawn "$device" defaults write "$preferences" GraphiteWelcomeTourShown -bool true
  xcrun simctl spawn "$device" defaults write "$preferences" GraphiteDefaultNoteView "$view"
  xcrun simctl spawn "$device" defaults delete "$preferences" "GraphiteDocumentPlaces.$vault_identifier" 2>/dev/null || true
  xcrun simctl spawn "$device" defaults delete "$preferences" GraphiteUsesVaultTheme 2>/dev/null || true
  print -rn -- "$appearance_original" > "$appearance_file"
  top="$(option_of "$shot_options" top)"; split="$(option_of "$shot_options" split)"; snippet="$(option_of "$shot_options" snippet)"; crop="$(option_of "$shot_options" crop)"
  if [[ -n "$top" ]]; then
    xcrun simctl spawn "$device" defaults write "$preferences" "GraphiteDocumentPlaces.$vault_identifier" -data "$(hex_of "$(places_with_top "$file" "$top")")"
  fi
  if [[ -n "$split" ]]; then
    xcrun simctl spawn "$device" defaults write "$preferences" "GraphiteTabLayout.$vault_identifier" -data "$(hex_of "$(split_layout "$file" "${split%%:*}" "${split#*:}")")"
  fi
  if [[ -n "$snippet" ]]; then
    xcrun simctl spawn "$device" defaults write "$preferences" GraphiteUsesVaultTheme -bool true
    python3 -I -c 'import json, sys; settings = json.loads(sys.argv[2]); settings["enabledCssSnippets"] = [sys.argv[3]]; open(sys.argv[1], "w").write(json.dumps(settings, indent=2))' \
      "$appearance_file" "$appearance_original" "$snippet"
  fi
  xcrun simctl ui "$device" appearance "$appearance"
  xcrun simctl launch "$device" "$bundle" >/dev/null
  sleep 9
  raw="$output/.raw.png"
  xcrun simctl io "$device" screenshot "$raw" >/dev/null 2>&1
  picture="$output/$family - $name.jpg"
  if [[ -n "$crop" ]]; then
    raw_height=$(sips -g pixelHeight "$raw" | awk '/pixelHeight/ { print $2 }'); raw_width=$(sips -g pixelWidth "$raw" | awk '/pixelWidth/ { print $2 }')
    crop_top=$(awk -v from="${crop%%:*}" -v height="$raw_height" 'BEGIN { printf "%d", from * height }')
    crop_height=$(awk -v from="${crop%%:*}" -v to="${crop#*:}" -v height="$raw_height" 'BEGIN { printf "%d", (to - from) * height }')
    sips --cropToHeightWidth "$crop_height" "$raw_width" --cropOffset "$crop_top" 0 "$raw" >/dev/null
  fi
  sips -s format jpeg -s formatOptions 62 --resampleWidth "$width" "$raw" --out "$picture" >/dev/null
  rm -f "$raw"
  print "$picture: $(( $(stat -f %z "$picture") / 1024 )) KB"
done

xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
print -rn -- "$appearance_original" > "$appearance_file"
xcrun simctl ui "$device" appearance light
