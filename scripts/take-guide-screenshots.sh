#!/bin/zsh
# Take the pictures of the app that the Graphite Guide vault shows (Docs/Guide-vault-todo.md, section 2), in an iPad or
# iPhone simulator, from the guide vault itself.
#
# The simulator gets a copy of Guide/Graphite Guide as its only vault. For each picture the app is quit, told which file
# to open at launch (the vault's last opened document, with no tabs remembered) and in which view and appearance, then
# launched and photographed. The pictures are written as small JPEGs into the vault's Attachments/Screenshots folder.
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
)

hex_of() { print -rn -- "$1" | xxd -p | tr -d '\n'; }

for shot in "${shots[@]}"; do
  IFS='|' read -r name file view appearance <<< "$shot"
  if (( ${#only} )) && (( ! ${only[(Ie)$name]} )); then continue; fi
  xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
  vaults="{\"vaults\":[{\"location\":{\"anchor\":{\"applicationDocuments\":{}},\"relativePath\":\"$vault_name\"},\"id\":\"$vault_identifier\",\"name\":\"$vault_name\",\"lastKnownPath\":\"$container/Documents/$vault_name\",\"lastOpenedDate\":816480000.0,\"lastOpenedDocument\":{\"rawValue\":\"$file\"}}]}"
  xcrun simctl spawn "$device" defaults write "$preferences" GraphiteKnownVaults -data "$(hex_of "$vaults")"
  xcrun simctl spawn "$device" defaults delete "$preferences" "GraphiteTabLayout.$vault_identifier" 2>/dev/null || true
  xcrun simctl spawn "$device" defaults delete "$preferences" "GraphiteNoteViews.$vault_identifier" 2>/dev/null || true
  xcrun simctl spawn "$device" defaults write "$preferences" GraphiteWelcomeTourShown -bool true
  xcrun simctl spawn "$device" defaults write "$preferences" GraphiteDefaultNoteView "$view"
  xcrun simctl ui "$device" appearance "$appearance"
  xcrun simctl launch "$device" "$bundle" >/dev/null
  sleep 9
  raw="$output/.raw.png"
  xcrun simctl io "$device" screenshot "$raw" >/dev/null 2>&1
  picture="$output/$family - $name.jpg"
  sips -s format jpeg -s formatOptions 62 --resampleWidth "$width" "$raw" --out "$picture" >/dev/null
  rm -f "$raw"
  print "$picture: $(( $(stat -f %z "$picture") / 1024 )) KB"
done

xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
xcrun simctl ui "$device" appearance light
