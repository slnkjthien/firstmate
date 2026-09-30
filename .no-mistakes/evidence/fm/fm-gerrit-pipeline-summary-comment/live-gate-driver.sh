#!/usr/bin/env bash
# Drives bin/fm-dod-lib.sh fm_dod_accept_ship_done (the no-mistakes Gerrit ready gate)
# against the REAL gerrit-axi and the REAL gerrit.spectralink.com change 186702 (read-only).
# Only `no-mistakes axi status` (run custody) is faked. The worktree is a scratch fetch of
# the change's current patch set 3.
ROOT=$1 WT=$2 NMBIN=$3
URL=https://gerrit.spectralink.com/c/spectralink/apps/SlnkDeviceSettings/+/186702
run() {  # <label> <marker-override-or-empty> <done line>
  echo "=== $1"
  echo "done line: $3"
  out=$(PATH="$NMBIN:$PATH" bash -c '. "$1/bin/fm-timeout-lib.sh"; . "$1/bin/fm-dod-lib.sh"
    [ -z "$5" ] || FM_DOD_GERRIT_SUMMARY_MARKER=$5
    echo "marker: $FM_DOD_GERRIT_SUMMARY_MARKER" >&2
    fm_dod_accept_ship_done ship no-mistakes "$2" "$2" "$3" "" "" "" ' _ "$ROOT" "$WT" "$3" x "$2" 2>&1); rc=$?
  printf '%s\nrc=%s (%s)\n\n' "$out" "$rc" "$([ $rc = 0 ] && echo ACCEPTED || echo REFUSED)"
}
run "1. worker skipped the post (real server has no summary message)" "" \
  "done: PR $URL published for review; pipeline summary posted on patch set 3"
run "2. summary present on current PS3 (marker = a real PS3 message line), report names PS3" \
  "Patch set 3 answers the AI review" "done: PR $URL published for review; pipeline summary posted on patch set 3"
run "3. summary present, report names stale PS2" \
  "Patch set 3 answers the AI review" "done: PR $URL published for review; pipeline summary posted on patch set 2"
run "4. summary present, report has no patch-set suffix" \
  "Patch set 3 answers the AI review" "done: PR $URL published for review"
run "5. summary only on superseded PS1 (marker only on PS1 message)" \
  "Uploaded patch set 1." "done: PR $URL published for review; pipeline summary posted on patch set 1"
echo "=== 6. unreadable change (bogus change number 999999999)"
out=$(PATH="$NMBIN:$PATH" bash -c '. "$1/bin/fm-timeout-lib.sh"; . "$1/bin/fm-dod-lib.sh"
  fm_dod_accept_ship_done ship no-mistakes "$2" "$2" "done: PR https://gerrit.spectralink.com/c/spectralink/apps/SlnkDeviceSettings/+/999999999 published for review; pipeline summary posted on patch set 1"' _ "$ROOT" "$WT" 2>&1); rc=$?
printf '%s\nrc=%s\n\n' "$out" "$rc"
echo "=== 7. HEAD moved after publishing (commit after publish), summary present"
git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m tmp >/dev/null
echo change > "$WT/.live-extra"; git -C "$WT" add .live-extra; git -C "$WT" -c user.email=t@t -c user.name=t commit -q -m extra
run "7" "Patch set 3 answers the AI review" "done: PR $URL published for review; pipeline summary posted on patch set 3"
git -C "$WT" reset -q --hard FETCH_HEAD
