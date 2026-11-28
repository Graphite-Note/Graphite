#!/bin/zsh
# File: measure-plugin-runtime.sh
# Layer: Tests
# Description: Samples the plugin runtime's web content processes in a simulator while
#   CommunityPluginRealVaultMeasurementHostedTests holds each phase.
# Authors: Bahey Shalash
# Version: 0.1
# Date: 28/11/2026
#
# Usage: tools/measure-plugin-runtime.sh <simulator udid> <made-up vault folder> <report file>
#
# The hosted test writes `<vault>.holding-<phase>` when a
# phase settles. For each, this script finds the app and the simulator's WebKit web content
# processes (on the Mac they are children of the simulator's `launchd_sim`), reads `footprint` of
# each every two seconds for thirty seconds, while the plugins index the vault in the background,
# appends the largest and the last reading per process to the report, and writes
# `<vault>.sampled-<phase>` so the test goes on. It ends after the last phase, `views-shown`.
set -u
setopt null_glob
udid=$1 vault=$2 report=$3
phases=(plugins-loaded blocks-shown views-shown)
rm -f "$vault".holding-* "$vault".sampled-*
for phase in $phases; do
  until [[ -f "$vault.holding-$phase" ]]; do sleep 1; done
  sleep 2 # lets the phase's last layout and garbage collection end before reading
  simulator_launchd=$(ps -axo pid,command | awk -v device="$udid" '$2 == "launchd_sim" && index($3, device) { print $1 }')
  footprint_megabytes() {
    footprint "$1" 2>/dev/null | awk '/Footprint:/ { for (i = 1; i < NF; i++) if ($i == "Footprint:") { value = $(i+1); unit = $(i+2) } if (unit == "GB") value *= 1024; if (unit == "KB") value /= 1024; print int(value); exit }'
  }
  app_pid=$(ps -axo pid,ppid,command | awk -v parent="$simulator_launchd" '$2 == parent && /Graphite\.app\/Graphite/ { print $1; exit }')
  typeset -A largest last
  largest=() last=()
  for reading in {1..15}; do
    for pid in $app_pid $(ps -axo pid,ppid,command | awk -v parent="$simulator_launchd" '$2 == parent && /com\.apple\.WebKit\.WebContent/ { print $1 }'); do
      megabytes=$(footprint_megabytes "$pid")
      [[ -z "$megabytes" ]] && continue
      last[$pid]=$megabytes
      (( megabytes > ${largest[$pid]:-0} )) && largest[$pid]=$megabytes
    done
    sleep 2
  done
  app_megabytes="${largest[$app_pid]:-0}/${last[$app_pid]:-0}"
  details=()
  for pid in ${(k)last}; do
    [[ "$pid" == "$app_pid" ]] && continue
    details+=("$pid:${largest[$pid]}/${last[$pid]}MB")
  done
  echo "$phase app=${app_megabytes}MB web_content (largest/last)=${details[*]}" | tee -a "$report"
  touch "$vault.sampled-$phase"
done
