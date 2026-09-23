#!/usr/bin/env bash
# Live driver: firstmate's Gerrit done gate, arming, and merge poll against the
# real gerrit.spectralink.com server (read-only: show/status only, no publish).
set -u
ROOT=$1
S=$(mktemp -d /tmp/fm-gerrit-live.XXXXXX)
trap 'rm -rf "$S"' EXIT
HOST=gerrit.spectralink.com
MERGED_URL=https://$HOST/c/spectralink/apps/SlnkFindMy/+/182804   # current PS rev 45f3115
MERGED_REV=45f31158029aab1c167c4d9f2b25c70eb60971c8
say() { printf '\n=== %s\n' "$*"; }

git clone -q ~/Code/SlnkFindMy "$S/wt"
git -C "$S/wt" remote set-url origin ssh://jthien@$HOST:29418/spectralink/apps/SlnkFindMy
git -C "$S/wt" checkout -q -b fm/live "$MERGED_REV"
git -C "$S/wt" -c user.name=t -c user.email=t@t config user.name t; git -C "$S/wt" config user.email t@t

gate() {  # <mode> <line> [state id meta]
  bash -c '. "$1/bin/fm-timeout-lib.sh"; . "$1/bin/fm-dod-lib.sh"; shift
    out=$(fm_dod_accept_ship_done ship "$@"); rc=$?; echo "rc=$rc ${out:+reason: $out}"' \
    _ "$ROOT" "$1" "$S/wt" "$S/wt" "$2" "${3:-}" "${4:-}" "${5:-}"
}

say "S5a HEAD is exactly the change's current patch set ($MERGED_REV), direct-PR"
gate direct-PR "done: PR $MERGED_URL published for review"

say "S5b HEAD is a squash-equivalent commit (same tree, new parent/message), no-mistakes"
sq=$(git -C "$S/wt" commit-tree "HEAD^{tree}" -p HEAD~2 -m "squashed locally")
git -C "$S/wt" reset -q --hard "$sq"; git -C "$S/wt" log --oneline -1
gate no-mistakes "done: PR $MERGED_URL published for review"

say "S5c worker committed after publishing; HEAD reachable from refs/remotes/no-mistakes/* (gate push) - must still refuse"
echo extra > "$S/wt/extra.txt"; git -C "$S/wt" add extra.txt; git -C "$S/wt" commit -q -m "post-publish commit"
git -C "$S/wt" update-ref refs/remotes/no-mistakes/fm/live HEAD
git -C "$S/wt" branch -r --contains HEAD
gate no-mistakes "done: PR $MERGED_URL published for review"

say "S5d same for direct-PR"
gate direct-PR "done: PR $MERGED_URL published for review"

say "S5e done names a change number that does not exist on the server"
gate direct-PR "done: PR https://$HOST/c/spectralink/apps/SlnkFindMy/+/999999999 published for review"

say "S6 fm-pr-check.sh arming a Gerrit change (scratch FM_HOME)"
mkdir -p "$S/root/bin" "$S/home/state" "$S/home/data" "$S/home/config"
printf '#!/bin/sh\nexit 0\n' > "$S/root/bin/fm-guard.sh"; chmod +x "$S/root/bin/fm-guard.sh"
git -C "$S/wt" reset -q --hard "$MERGED_REV"; git -C "$S/wt" update-ref -d refs/remotes/no-mistakes/fm/live
mk_meta() { printf '%s\n' "window=fm-$1" "endpoint_task_id=$1" "worktree=$S/wt" "project=$S/wt" kind=ship "mode=$2" > "$S/home/state/$1.meta"; chmod 600 "$S/home/state/$1.meta"; }
check() { FM_ROOT_OVERRIDE="$S/root" FM_HOME="$S/home" "$ROOT/bin/fm-pr-check.sh" "$@"; echo "rc=$?"; }

echo "-- S6a mismatched HEAD refused, nothing recorded"
echo extra > "$S/wt/extra.txt"; git -C "$S/wt" add extra.txt; git -C "$S/wt" commit -q -m "post-publish commit"
git -C "$S/wt" update-ref refs/remotes/no-mistakes/fm/live HEAD
mk_meta t-bad no-mistakes
check t-bad "$MERGED_URL" 2>&1
grep '^pr=' "$S/home/state/t-bad.meta" || echo "(no pr= recorded)"; ls "$S/home/state" | grep -c 't-bad.check.sh' || true

echo "-- S6b matching HEAD armed; pr= recorded, no pr_head"
git -C "$S/wt" reset -q --hard "$MERGED_REV"
mk_meta t-ok direct-PR
check t-ok "$MERGED_URL" 2>&1
grep -E '^pr(_head)?=' "$S/home/state/t-ok.meta"; ls "$S/home/state" | grep 't-ok'

say "S7 after arming, worker copy diverges (as if server rebased); recorded pr= still accepts with NO gerrit-axi call"
echo more > "$S/wt/more.txt"; git -C "$S/wt" add more.txt; git -C "$S/wt" commit -q -m diverge
mkdir -p "$S/tripwire"; printf '#!/bin/sh\necho "gerrit-axi called: $*" >> %s/tripwire.log\nexit 1\n' "$S" > "$S/tripwire/gerrit-axi"; chmod +x "$S/tripwire/gerrit-axi"
PATH="$S/tripwire:$PATH" gate direct-PR "done: PR $MERGED_URL published for review" "$S/home/state" t-ok "$S/home/state/t-ok.meta"
[ -s "$S/tripwire.log" ] && cat "$S/tripwire.log" || echo "(gerrit-axi was not invoked)"
echo "-- contrast: an unrecorded task with the same diverged HEAD is refused (live read)"
gate direct-PR "done: PR $MERGED_URL published for review" "$S/home/state" t-bad "$S/home/state/t-bad.meta"

say "S8 merge poll (fm-pr-poll.sh) against real changes"
P=$ROOT/bin/fm-pr-poll.sh
echo "-- merged change 182804:"; "$P" --validated gerrit "$MERGED_URL" $HOST spectralink/apps/SlnkFindMy 182804; echo "rc=$?"
echo "-- open change 186649 (expect silence):"; "$P" --validated gerrit https://$HOST/c/spectralink/apps/SlnkOTA/+/186649 $HOST spectralink/apps/SlnkOTA 186649; echo "rc=$?"
echo "-- abandoned change 181792 (expect silence):"; "$P" --validated gerrit https://$HOST/c/spectralink/apps/SlnkDeviceSettings/+/181792 $HOST spectralink/apps/SlnkDeviceSettings 181792; echo "rc=$?"
echo "-- armed sidecar check script for t-ok (run as fm-watch.sh does: bash <check>, from /):"; (cd / && timeout 30 bash "$S/home/state/t-ok.check.sh"); echo "rc=$?"
