#!/bin/bash
# Runs the checks that come before every TestFlight upload, one at a time, in the order of Docs/Release-checks.md: the
# rule checks, the full Mac package suite, the release vault pass on the Mac, the full hosted suite on an iPad simulator,
# the release vault pass on the iPad and on an iPhone simulator made for the run, and the size report. It stops at the
# first failure that is not on the known list below, and prints a summary to paste into the upload's What to Test.
#
# Nothing may make a sound: every test run is watched, and stopped at once if the Mac's or the simulator's audio output
# opens (an "audio-out" assertion in `pmset -g assertions`). Assertions already open when a run starts, by another app,
# are printed at its start and left alone. One made during the run stops it, unless another app made it: an app in
# /Applications or /System/Applications other than Xcode, Simulator and Graphite, or a system sound such an app or a
# system service asked for (the browser, the Claude app, Messages, AirDrop's tone); that one is printed and left alone.
# So is one another session's Mac tests asked for. A sound with no known source, any simulator's audio and any sound
# asked for by the run's own xctest, by Graphite or by a simulator stops the run.
#
# The build folder must be outside iCloud (codesign fails in iCloud's Desktop) and is created if needed; logs, result
# bundles and screenshots go there too. Only one build may run on the Mac at a time: the script waits for others to end.
#
# Usage: scripts/release-check.sh <build folder outside iCloud> [--ipad <simulator udid>] [--from <step>]
#   for example: scripts/release-check.sh /tmp/graphite-release-check
#   --from starts at a later step (rules, mac-suite, mac-pass, ios-build, hosted-suite, ipad-pass, iphone-pass, sizes) after
#   an earlier run passed the steps before it.
set -u
if [ $# -lt 1 ]; then sed -n '2,17p' "$0"; exit 2; fi
build_folder=$1; shift
ipad_udid=""
first_step=rules
while [ $# -gt 0 ]; do
  case "$1" in
    --ipad) ipad_udid=$2; shift 2 ;;
    --from) first_step=$2; shift 2 ;;
    *) echo "Unknown option $1" >&2; sed -n '2,17p' "$0"; exit 2 ;;
  esac
done
repository_root=$(cd "$(dirname "$0")/.." && pwd)
case "$build_folder" in
  "$HOME/Desktop"*|"$HOME/Documents"*|*"Mobile Documents"*) echo "The build folder must be outside iCloud: $build_folder" >&2; exit 2 ;;
esac
mkdir -p "$build_folder"
build_folder=$(cd "$build_folder" && pwd)
summary="$build_folder/release-check-summary.txt"
cd "$repository_root"

# Failures known on main that are not a release's own: one place, each with why. A failure of a test named here (a whole
# class, or Class/test) is reported in the summary and does not stop the run; any other failure stops it.
KNOWN_FAILURES=(
  "PDFTextBoxesTests"                  # hosted: three tests failing on main in the iPad simulator (2026-11-12)
  "ReadAloudLectureHighlightTests/testReadAloudPenReadsFromATappedWordThenExactlyToASecondTap"  # hosted: failing on main (2026-11-12)
  "UiPdfSessionFixTests"               # Mac: timing under --parallel and load
  "PixelEraserPassTests"               # Mac: timing under --parallel and load
  "BaseWholeVaultTimingTests"          # Mac: timing under --parallel and load
  "ReadingViewStartingPlaceTests"      # Mac: timing under --parallel and load
  "ScalingChecksTests/testWorkInProportionToItsInputPasses"  # Mac: timing under --parallel and load (8.5x for 4x at load 50, 2026-11-19; passes alone)
  "EditingContinuityTests/testLongNoteRestyleCostWithAndWithoutATheme"  # hosted: 16.6 to 17.3 ms against 16.7 on a quiet Mac (Coverage.md); 28 ms with and without the theme at load 90 (2026-11-19)
  "FileTreeFilterHostedTests/testFilteringThirtyThousandFilesFitsInAFrame"  # hosted: 14 ms against 16 on a quiet simulator (File-tree-filter-todo.md); 22 ms at load 90 (2026-11-19)
)

steps=(rules mac-suite mac-pass ios-build hosted-suite ipad-pass iphone-pass sizes)
results=()
known_seen=()
started=no

report() { echo "$1" | tee -a "$summary"; }

is_known() {
  local failure=$1 known
  for known in "${KNOWN_FAILURES[@]}"; do
    [ "$failure" = "$known" ] || [ "${failure%%/*}" = "$known" ] && return 0
  done
  return 1
}

# The failed tests of a log, as Class/test, from swift test's and xcodebuild's lines.
failed_tests() {
  grep -hoE "Test [Cc]ase '(-\[[A-Za-z0-9_]+\.[A-Za-z0-9_]+ [A-Za-z0-9_]+\]|[A-Za-z0-9_]+\.[A-Za-z0-9_]+\(\))' failed" "$1" \
    | sed -E "s/.*'-\[[A-Za-z0-9_]+\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]'.*/\1\/\2/; s/.*'([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\(\)'.*/\1\/\2/" | sort -u
}

# Fails the step when a failed test is not known; records the known ones seen.
check_failures() {
  local log=$1 failure unknown=0
  for failure in $(failed_tests "$log"); do
    if is_known "$failure"; then known_seen+=("$failure"); else report "  FAILED: $failure"; unknown=1; fi
  done
  return $unknown
}

# The audio-out assertions of a `pmset -g assertions` listing (the present one when none is given).
audio_assertion_ids() { { [ $# -gt 0 ] && echo "$1" || pmset -g assertions 2>/dev/null; } | grep -B2 -iE "audio-out" | grep -oE "\[0x[0-9a-f]+\]" | sort -u; }

# Prints who made an audio assertion and succeeds when it is another app's, not the run's (see the top of the file).
# systemsoundserverd plays the Mac's own sounds and logs the process that asked for each one.
# Whether a process descends from another (the run's own tests do).
descends_from() {
  local process=$1 ancestor=$2
  while [ -n "$process" ] && [ "$process" -gt 1 ]; do
    [ "$process" = "$ancestor" ] && return 0
    process=$(ps -o ppid= -p "$process" 2>/dev/null | tr -d ' ')
  done
  return 1
}

# A short sound can be over before it is looked at, so the listing that showed the assertion is passed in. A Mac test
# process (xctest) that is not the run's own is another session's suite, and its sound is not the run's.
foreign_audio_source() {
  local assertion=$1 listing=$2 run=$3 creator creator_path clients client others=""
  creator=$(echo "$listing" | grep -A3 -F "$assertion" | grep -oE "Created for PID: [0-9]+" | grep -oE "[0-9]+$" | head -1)
  [ -n "$creator" ] || return 1
  creator_path=$(ps -p "$creator" -o comm= 2>/dev/null)
  case "$creator_path" in
    /Applications/Xcode*|/Applications/Simulator*|/Applications/Graphite*|*CoreSimulator*|*Simulator.app*) return 1 ;;
    /Applications/*|/System/Applications/*) echo "${creator_path##*/} (pid $creator)"; return 0 ;;
    */systemsoundserverd)
      clients=$(/usr/bin/log show --last 10s --info --style compact --predicate 'process == "systemsoundserverd" AND eventMessage CONTAINS "Incoming Request"' 2>/dev/null \
        | grep -oE "inClientPID [0-9]+\([^)]*\)" | sort -u | tr '\n' ' ')
      [ -n "$clients" ] || return 1
      for client in $(echo "$clients" | grep -oE "[0-9]+\([^)]*\)"); do
        case "$client" in
          *"(xctest)"|*"(swift-test)") descends_from "${client%%(*}" "$run" && return 1; others="$others another session's $client" ;;
          *"(Graphite"*|*"(launchd_sim)"|*"(Simulator"*) return 1 ;;
          *) others="$others $client" ;;
        esac
      done
      echo "a system sound asked for by$others"; return 0 ;;
  esac
  return 1
}

# Runs a command in the background with the audio watch; its output goes to the log. Returns 3 when audio opened.
run_watched() {
  local log=$1; shift
  local baseline opened run assertion source ours listing
  baseline=$(audio_assertion_ids)
  if [ -n "$baseline" ]; then echo "Audio assertions already open before the run, left alone: $(echo $baseline)" | tee "$log"; else : > "$log"; fi
  "$@" >> "$log" 2>&1 &
  run=$!
  while kill -0 "$run" 2>/dev/null; do
    listing=$(pmset -g assertions 2>/dev/null)
    opened=$(comm -13 <(echo "$baseline") <(audio_assertion_ids "$listing") | grep .)
    ours=""
    for assertion in $opened; do
      if source=$(foreign_audio_source "$assertion" "$listing" "$run"); then
        report "  audio output opened by another app during $(basename "$log"), left alone: $source"
        baseline=$(printf '%s\n%s\n' "$baseline" "$assertion" | grep . | sort -u)
      else
        ours="$ours $assertion"
      fi
    done
    opened=$(echo $ours)
    if [ -n "$opened" ]; then
      report "AUDIO OUTPUT OPENED during $(basename "$log"): $(echo "$listing" | grep -A3 -F "$opened" | tr -s ' ' | tr '\n' ' ')"
      # swift test --parallel numbers each test it starts ("[12/5050] Testing ..."); the others print "Test Case ... started".
      report "  while: $(grep -E "Test Case .* started|^\[[0-9]+/[0-9]+\] Testing " "$log" | tail -3 | tr '\n' ' ')"
      # The Mac's own sounds come from systemsoundserverd, which logs the process that asked for each one.
      report "  sounds asked for: $(/usr/bin/log show --last 1m --info --style compact --predicate 'process == "systemsoundserverd" AND eventMessage CONTAINS "Incoming Request"' 2>/dev/null | grep -oE "inClientPID [0-9]+\([^)]*\)" | sort -u | tr '\n' ' ')"
      pkill -P "$run" 2>/dev/null; kill "$run" 2>/dev/null; wait "$run" 2>/dev/null
      return 3
    fi
    sleep 0.5
  done
  wait "$run"
}

# Builds only: other sessions run tests one after another all day, and waiting for a moment with none never ended
# (2026-11-19). An xcodebuild that only runs tests (test-without-building) is not a build.
other_build_running() {
  ps -axo args | grep -E "^/Applications/Xcode[^ ]*\.app/.*/(swift-build|xcodebuild)( |$)" | grep -v "test-without-building" | grep -q .
}

wait_for_other_builds() {
  while other_build_running; do sleep 10; done
}

restore_package_resolved() { git checkout -- Graphite.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null; }

hosted_run() {
  local log=$1 udid=$2 result_bundle=$3 allowance=$4; shift 4
  rm -rf "$result_bundle"
  run_watched "$log" xcodebuild test-without-building -project Graphite.xcodeproj -scheme Graphite -destination "id=$udid" \
    -derivedDataPath "$build_folder/derived" -resultBundlePath "$result_bundle" -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance "$allowance" "$@"
}

step_rules() {
  local script status=0
  for script in check-rules check-imports check-test-registration check-defect-tests check-invariant-pins; do
    python3 "scripts/$script.py" > "$build_folder/$script.log" 2>&1 || { report "  $script failed: $(grep -m3 FAIL "$build_folder/$script.log")"; status=1; }
  done
  return $status
}

step_mac_suite() {
  wait_for_other_builds
  swift build --build-tests --scratch-path "$build_folder/swiftpm" > "$build_folder/mac-build.log" 2>&1 \
    || { report "  the Mac build failed: $(grep -m3 error: "$build_folder/mac-build.log")"; return 1; }
  run_watched "$build_folder/mac-suite.log" swift test --skip-build --parallel --scratch-path "$build_folder/swiftpm"
  local status=$?
  [ $status -eq 3 ] && return 1
  # Under --parallel, swift test numbers each test it starts ("[12/5050] Testing ...") instead of printing a total.
  report "  $(grep -oE '^\[[0-9]+/[0-9]+\]' "$build_folder/mac-suite.log" | tail -1 | tr -d '[]' | sed 's|/| of |') tests run"
  check_failures "$build_folder/mac-suite.log"
}

step_mac_pass() {
  mkdir -p "$build_folder/release-pass-mac"
  # The pass reuses the Mac suite's build; started here with --from, it builds first, or it would test the last build made
  # in this folder, whatever the checkout holds now (seen 2026-11-17).
  if [ "$first_step" = mac-pass ]; then
    wait_for_other_builds
    swift build --build-tests --scratch-path "$build_folder/swiftpm" > "$build_folder/mac-pass-build.log" 2>&1 || { report "  the build failed: $build_folder/mac-pass-build.log"; return 1; }
  fi
  run_watched "$build_folder/mac-pass.log" env GRAPHITE_RELEASE_PASS=1 GRAPHITE_RELEASE_PASS_SCREENSHOTS="$build_folder/release-pass-mac" \
    swift test --skip-build --scratch-path "$build_folder/swiftpm" --filter ReleaseVaultPassTests
  local status=$?
  grep -hE "GRAPHITE-RELEASE-(PASS|FINDING|KNOWN)" "$build_folder/mac-pass.log" | sed 's/^/  Mac: /' | tee -a "$summary"
  [ $status -eq 0 ] && grep -q "GRAPHITE-RELEASE-PASS" "$build_folder/mac-pass.log"
}

step_ios_build() {
  [ -n "$ipad_udid" ] || ipad_udid=$(python3 scripts/select-ipad-simulator.py) || return 1
  xcrun simctl boot "$ipad_udid" 2>/dev/null
  wait_for_other_builds
  xcodebuild build-for-testing -project Graphite.xcodeproj -scheme Graphite -destination "id=$ipad_udid" -derivedDataPath "$build_folder/derived" \
    -skipPackagePluginValidation -skipMacroValidation > "$build_folder/ios-build.log" 2>&1
  local status=$?
  restore_package_resolved
  [ $status -eq 0 ] || report "  the iOS build failed: $(grep -m3 error: "$build_folder/ios-build.log")"
  return $status
}

step_hosted_suite() {
  [ -n "$ipad_udid" ] || ipad_udid=$(python3 scripts/select-ipad-simulator.py) || return 1
  hosted_run "$build_folder/hosted-suite.log" "$ipad_udid" "$build_folder/hosted-suite.xcresult" 240
  [ $? -eq 3 ] && return 1
  report "  $(grep -E 'Executed [0-9]+ tests' "$build_folder/hosted-suite.log" | tail -1 | sed -E 's/^[[:space:]]+//')"
  check_failures "$build_folder/hosted-suite.log"
}

# The pass's screenshots are the result bundle's attachments; they are exported next to it.
pass_on_simulator() {
  local name=$1 udid=$2
  TEST_RUNNER_GRAPHITE_RELEASE_PASS=1 hosted_run "$build_folder/$name.log" "$udid" "$build_folder/$name.xcresult" 1200 \
    -only-testing:GraphiteIntegrationTests/ReleaseVaultPassHostedTests
  local status=$?
  grep -hE "GRAPHITE-RELEASE-(PASS|FINDING|KNOWN)" "$build_folder/$name.log" | sed "s/^/  $name: /" | tee -a "$summary"
  rm -rf "$build_folder/$name-screenshots"
  xcrun xcresulttool export attachments --path "$build_folder/$name.xcresult" --output-path "$build_folder/$name-screenshots" > /dev/null 2>&1
  [ $status -eq 0 ] && grep -q "GRAPHITE-RELEASE-PASS" "$build_folder/$name.log"
}

step_ipad_pass() {
  [ -n "$ipad_udid" ] || ipad_udid=$(python3 scripts/select-ipad-simulator.py) || return 1
  pass_on_simulator ipad-pass "$ipad_udid"
}

# An iPhone made for the run on the newest iOS runtime, and deleted after it, so no other session's simulator is used.
step_iphone_pass() {
  local runtime device_type iphone_udid status
  # A runtime named iOS-<major>-<minor> only: a device's own runtime (iOS-27-2-iPhone19-4) is not for every model.
  runtime=$(xcrun simctl list runtimes available | grep -oE "com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+-[0-9]+$" | sort -t- -k2,2n -k3,3n | tail -1)
  device_type=$(xcrun simctl list devicetypes | grep -oE "com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[0-9]+-Pro\)" | tr -d ')' \
    | sort -t- -k2,2n | tail -1)
  [ -n "$runtime" ] && [ -n "$device_type" ] || { report "  no iPhone simulator can be made"; return 1; }
  iphone_udid=$(xcrun simctl create "Graphite Release Check iPhone" "$device_type" "$runtime") || return 1
  xcrun simctl boot "$iphone_udid"
  pass_on_simulator iphone-pass "$iphone_udid"
  status=$?
  xcrun simctl shutdown "$iphone_udid" 2>/dev/null
  xcrun simctl delete "$iphone_udid"
  return $status
}

step_sizes() {
  python3 scripts/size-report.py > "$build_folder/size-report.log" 2>&1 || { report "  $(tail -3 "$build_folder/size-report.log")"; return 1; }
}

: > "$summary"
report "Release check of $(git rev-parse --short HEAD) on $(date '+%Y-%m-%d %H:%M'), build folder $build_folder"
for step in "${steps[@]}"; do
  [ "$step" = "$first_step" ] && started=yes
  [ "$started" = yes ] || continue
  report "== $step"
  start_seconds=$SECONDS
  if "step_${step//-/_}"; then
    results+=("$step: passed in $(( (SECONDS - start_seconds) / 60 )) min")
  else
    results+=("$step: FAILED")
    report "Stopped at $step. Logs are in $build_folder."
    break
  fi
done
[ -n "$ipad_udid" ] && xcrun simctl shutdown "$ipad_udid" 2>/dev/null

report ""
report "Summary"
for result in "${results[@]}"; do report "- $result"; done
if [ ${#known_seen[@]} -gt 0 ]; then report "- known failures seen: $(printf '%s\n' "${known_seen[@]}" | sort -u | tr '\n' ' ')"; fi
case "${results[*]}" in *FAILED*) exit 1 ;; esac
[ "$started" = yes ] || { echo "Unknown step $first_step" >&2; exit 2; }
[ "$first_step" = rules ] || exit 0
report ""
report "What to Test: this build passed the release checks on $(date '+%Y-%m-%d'): the rule checks, the full Mac suite and the full"
report "hosted iPad suite, and the release vault (Tests/ReleaseVault, every note in Live Preview, reading view and source mode, every"
report "PDF, canvas, base and picture in its own view) on the Mac, an iPad and an iPhone simulator. Try on the device what a simulator"
report "cannot show: Apple Pencil, the keyboard and trackpad, memory and speed with your own vault."
exit 0
