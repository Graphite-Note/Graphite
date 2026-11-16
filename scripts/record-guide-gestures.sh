#!/bin/zsh
# File: record-guide-gestures.sh
# Layer: Scripts
# Description: Records the Graphite Guide's animated pictures of gestures (Docs/Guide-vault-todo.md, section 2) in an iPad
#              simulator: GuideGestureRecordingsHostedTests plays them in Graphite's window on the guide vault while the
#              simulator's screen is recorded, each gesture on its own, and made into a small looping GIF with no sound in the
#              vault's Attachments/Screenshots folder.
# Authors: Bahey Shalash
# Version: 0.1
# Date: 16/11/2026
#
# The simulator must be one of your own, and the hosted tests built for it with build-for-testing into the derived data
# folder given. The test runs through run-hosted-suite-silently.sh, which stops it if the simulator's audio output opens.
#
# Usage:
#   scripts/record-guide-gestures.sh <simulator UDID> <derived data folder> <work folder>

set -e
device="$1"; derived="$2"; work="$3"
repository="${0:A:h:h}"
output="$repository/Guide/Graphite Guide/Attachments/Screenshots"
mkdir -p "$work"
marks="$work/marks.txt"
rm -f "$work"/*.mov(N) "$work"/*.log(N) "$work"/*.pid(N) "$marks"(N) "$marks".*(N)

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl spawn "$device" defaults write com.apple.Preferences KeyboardClicks -bool false
xcrun simctl ui "$device" appearance light

# The test writes "<gesture> begin" and "<gesture> end" into the marks file and waits for an answer: each gesture is
# recorded on its own, from when recordVideo says it has started to when the test says the gesture is done.
touch "$marks"
(
  tail -n +1 -f "$marks" | while read -r gesture phase; do
    if [[ "$phase" == begin ]]; then
      xcrun simctl io "$device" recordVideo --codec=h264 --force "$work/$gesture.mov" > "$work/$gesture.log" 2>&1 &
      print $! > "$work/$gesture.pid"
      until grep -q "Recording started" "$work/$gesture.log" 2>/dev/null; do sleep 0.05; done
      sleep 0.2
      touch "$marks.begin-$gesture"
    else
      kill -INT "$(cat "$work/$gesture.pid")"
      while kill -0 "$(cat "$work/$gesture.pid")" 2>/dev/null; do sleep 0.1; done
      touch "$marks.end-$gesture"
    fi
  done
) &
listener=$!

cd "$repository"
TEST_RUNNER_GRAPHITE_GUIDE_GESTURES="$marks" scripts/run-hosted-suite-silently.sh "$device" "$derived" test-without-building \
  -only-testing:GraphiteIntegrationTests/GuideGestureRecordingsHostedTests || test_status=$?
pkill -P "$listener" 2>/dev/null; kill "$listener" 2>/dev/null || true
for pid_file in "$work"/*.pid(N); do kill -INT "$(cat "$pid_file")" 2>/dev/null || true; done
if [ -n "${test_status:-}" ]; then echo "The test failed ($test_status): no pictures made." >&2; exit "$test_status"; fi

# gesture name|picture name|the part of the screen shown (an ffmpeg crop, the whole screen when empty)|width
pictures=(
  "switching-views|iPad - Switching views||560"
  "drawing|iPad - Writing on a page||560"
  "lasso|iPad - The lasso||560"
  "pen-colors|iPad - Choosing and arranging colours|crop=iw:ih*0.72:0:0,|640"
)
for picture in "${pictures[@]}"; do
  IFS='|' read -r gesture name crop width <<< "$picture"
  gif="$output/$name.gif"
  ffmpeg -loglevel error -y -an -i "$work/$gesture.mov" \
    -vf "${crop}tpad=stop_mode=clone:stop_duration=1.5,fps=10,scale=${width}:-1:flags=lanczos,split[frames][again];[again]palettegen=max_colors=96:stats_mode=diff[palette];[frames][palette]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    -loop 0 "$gif"
  print "$gif: $(( $(stat -f %z "$gif") / 1024 )) KB"
done
