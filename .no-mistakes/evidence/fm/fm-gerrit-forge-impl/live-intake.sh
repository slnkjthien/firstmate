#!/usr/bin/env bash
# Live driver: project intake (forge detect), registry posture, brief scaffold,
# and spawn forge agreement, run against a scratch FM_HOME and a local clone of
# the real Gerrit-hosted SlnkFindMy project. Nothing is launched or published.
set -u
ROOT=$1
S=$(mktemp -d /tmp/fm-gerrit-intake.XXXXXX)
trap 'rm -rf "$S"' EXIT
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; "$@"; echo "rc=$?"; }

say "S1 forge detection at intake"
echo "-- the real SlnkFindMy clone (~/Code/SlnkFindMy, read-only):"
run "$ROOT/bin/fm-forge-detect.sh" ~/Code/SlnkFindMy
echo "-- a GitHub-hosted clone (this firstmate worktree):"
run "$ROOT/bin/fm-forge-detect.sh" "$ROOT"
echo "-- an HTTPS clone whose push refspec targets refs/for/:"
git clone -q ~/Code/SlnkFindMy "$S/https"; git -C "$S/https" remote set-url origin https://gerrit.example/a/p
git -C "$S/https" config remote.origin.push 'HEAD:refs/for/master'
run "$ROOT/bin/fm-forge-detect.sh" "$S/https"
echo "-- not a git work tree:"
mkdir "$S/plain"; run "$ROOT/bin/fm-forge-detect.sh" "$S/plain"

H=$S/home; mkdir -p "$H/data" "$H/state" "$H/config"
mode() { printf '%s\n' "$1" > "$H/data/projects.md"; printf 'registry: %s\n' "$1"; FM_HOME=$H "$ROOT/bin/fm-project-mode.sh" SlnkFindMy; echo "rc=$?"; }
say "S2 registry posture from data/projects.md"
mode '- SlnkFindMy [no-mistakes forge=gerrit] - Find My app (added 2026-09-23)'
mode '- SlnkFindMy [direct-PR forge=gerrit] - Find My app (added 2026-09-23)'
mode '- SlnkFindMy [no-mistakes] - Find My app (added 2026-09-23)'
echo "-- adversarial:"
mode '- SlnkFindMy [local-only forge=gerrit] - Find My app (added 2026-09-23)'
mode '- SlnkFindMy [no-mistakes forg=gerrit] - Find My app (added 2026-09-23)'
mode '- SlnkFindMy [no-mistakes forge=gerit] - Find My app (added 2026-09-23)'
mode '- SlnkFindMy [gerrit] - Find My app (added 2026-09-23)'
mode '- SlnkFindMy [no-mistakes forge=gerrit +yolo] - Find My app (added 2026-09-23)'

say "S3 brief scaffold"
B="$ROOT/bin/fm-brief.sh"
brief() { printf '$ fm-brief.sh %s\n' "$*"; FM_HOME=$H "$B" "$@"; echo "rc=$?"; }
brief t-dpr SlnkFindMy --mode direct-PR --forge gerrit
brief t-nm SlnkFindMy --mode no-mistakes --forge gerrit
echo "-- adversarial:"
brief t-stack SlnkFindMy --mode direct-PR --forge gerrit --shape stack
brief t-lo SlnkFindMy --mode local-only --forge gerrit
brief t-typo SlnkFindMy --mode direct-PR --forge gitlab
brief t-shape SlnkFindMy --mode direct-PR --shape squash
brief t-scout SlnkFindMy --scout --forge gerrit
echo "-- rendered Definition of done, direct-PR forge=gerrit:"
sed -n '/^# Definition of done/,$p' "$H/data/t-dpr/brief.md"
echo "-- safety rule 1 on a gerrit brief:"
grep -m1 '^1\. ' "$H/data/t-dpr/brief.md"
echo "-- rendered Definition of done, no-mistakes forge=gerrit:"
sed -n '/^# Definition of done/,$p' "$H/data/t-nm/brief.md"
cp "$H/data/t-dpr/brief.md" "$(dirname "$0")/brief-direct-PR-gerrit.md"
cp "$H/data/t-nm/brief.md" "$(dirname "$0")/brief-no-mistakes-gerrit.md"

say "S4 spawn forge agreement (fake tmux; nothing launches)"
mkdir -p "$S/fakebin" "$S/projects"; printf '#!/bin/sh\nexit 1\n' > "$S/fakebin/tmux"; chmod +x "$S/fakebin/tmux"
git clone -q ~/Code/SlnkFindMy "$S/projects/SlnkFindMy"
printf '%s\n' '- SlnkFindMy [no-mistakes forge=gerrit] - Find My app (added 2026-09-23)' > "$H/data/projects.md"
fill() { f=$H/data/$1/brief.md; c=$(cat "$f"); c=${c//'{TASK}'/Bump a dependency.}; c=${c//'{FIRSTMATE_SPEC}'/Ship it.}; printf '%s\n' "$c" > "$f"; }
spawn() { printf '$ fm-spawn.sh %s\n' "$*"; FM_ROOT_OVERRIDE='' FM_HOME=$H FM_STATE_OVERRIDE=$H/state FM_DATA_OVERRIDE=$H/data \
  FM_PROJECTS_OVERRIDE=$S/projects-unused FM_CONFIG_OVERRIDE=$H/config FM_SPAWN_NO_GUARD=1 FM_BACKEND=tmux \
  PATH="$S/fakebin:$PATH" "$ROOT/bin/fm-spawn.sh" "$@" 2>&1 | grep -iE 'forge|yolo|error|refus' | head -5; }
FM_HOME=$H "$B" s-plain SlnkFindMy --mode no-mistakes >/dev/null; fill s-plain
echo "-- gerrit-bound project, brief scaffolded without --forge (must refuse):"
spawn s-plain "$S/projects/SlnkFindMy" claude --mode no-mistakes --yolo off
ls "$H/state/s-plain.meta" 2>/dev/null || echo "(no task meta written)"
fill t-nm
echo "-- gerrit brief on gerrit project, --yolo on (must refuse):"
spawn t-nm "$S/projects/SlnkFindMy" claude --mode no-mistakes --yolo on
echo "-- gerrit brief on gerrit project, --yolo off (no forge refusal; stops later at fake tmux):"
spawn t-nm "$S/projects/SlnkFindMy" claude --mode no-mistakes --yolo off
echo "-- gerrit brief on an unbound project (must refuse):"
printf '%s\n' '- SlnkFindMy [no-mistakes] - Find My app (added 2026-09-23)' > "$H/data/projects.md"
fill t-dpr
spawn t-dpr "$S/projects/SlnkFindMy" claude --mode direct-PR --yolo off
echo "-- mistyped forge in registry (must refuse, not default):"
printf '%s\n' '- SlnkFindMy [no-mistakes forg=gerrit] - Find My app (added 2026-09-23)' > "$H/data/projects.md"
spawn t-dpr "$S/projects/SlnkFindMy" claude --mode direct-PR --yolo off
