#!/usr/bin/env bash
# Push -> wait for CI -> download APK -> copy to Zorin -> adb install onto the plugged-in phone.
# Usage: scripts/deploy.sh            (builds whatever is on origin/main after pushing)
set -euo pipefail

ZORIN="${ZORIN:-anhnt@192.168.1.231}"
cd "$(dirname "$0")/.."
OUT=build_out
rm -rf "$OUT" && mkdir -p "$OUT"

git push origin main
SHA=$(git rev-parse HEAD)

echo "Waiting for CI run of $SHA ..."
RUN_ID=""
for _ in $(seq 1 30); do
  RUN_ID=$(gh run list --workflow build.yml --commit "$SHA" --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
  [ -n "$RUN_ID" ] && break
  sleep 5
done
[ -n "$RUN_ID" ] || { echo "No CI run found for $SHA" >&2; exit 1; }

gh run watch "$RUN_ID" --exit-status
gh run download "$RUN_ID" -n app-release -D "$OUT"

APK="$OUT/app-release.apk"
[ -s "$APK" ] || { echo "APK missing" >&2; exit 1; }

# adb must see exactly a device in state 'device' before we install.
ssh -o BatchMode=yes "$ZORIN" 'adb devices | grep -w device >/dev/null' \
  || { echo "No authorised phone on $ZORIN (check USB debugging / Allow prompt)" >&2; exit 1; }

scp -q "$APK" "$ZORIN:/tmp/video_timer_player.apk"
ssh "$ZORIN" 'adb install -r /tmp/video_timer_player.apk'
echo OK
