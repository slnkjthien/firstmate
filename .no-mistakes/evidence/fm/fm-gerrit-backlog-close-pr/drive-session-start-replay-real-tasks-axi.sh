#!/usr/bin/env bash
# Session-start (fm-bootstrap) replay of a pending Gerrit close record as a
# pre-fix teardown left it, against the REAL installed tasks-axi (no wrapper).
# Replays twice to show it is not refused on every session start.
set -u
CHECKOUT=$1
cd "$CHECKOUT"
cut=$(awk '/^test_[a-z_0-9]+$/{print NR-1; exit}' tests/fm-backlog-atomicity.test.sh); defs=$(mktemp); head -n "$cut" tests/fm-backlog-atomicity.test.sh | sed "s#\$(dirname \"\${BASH_SOURCE\[0\]}\")#$CHECKOUT/tests#g" > "$defs"
. "$defs"; rm -f "$defs"
echo "tasks-axi $(tasks-axi --version); checkout HEAD: $(git rev-parse --short HEAD)"
id=replay-gerrit-b9 url=https://gerrit.example.com/c/project/+/12345
case_dir=$(make_home live-replay-gerrit)
add_item "$case_dir" "$id"; start_item "$case_dir" "$id"
printf 'id=%s\ndata=%s\nspawn_gen=spawn-replay\narg=--pr\narg=%s\n' "$id" "$(home_of "$case_dir")/data" "$url" \
  > "$(home_of "$case_dir")/state/$id.backlog-close"
echo "--- pending record before session start:"; cat "$(home_of "$case_dir")/state/$id.backlog-close"
echo "row state before: $(row_state "$case_dir" "$id")"
for n in 1 2; do
  echo; echo "=== session start #$n"
  run_bootstrap "$case_dir" | grep -iE "$id|backlog-close|canonical|close" | head -6
  echo "row state: $(row_state "$case_dir" "$id")"
  tasks-axi show "$id" --file "$(backlog_of "$case_dir")" --full | grep -E 'links:|body:'
  [ -e "$(home_of "$case_dir")/state/$id.backlog-close" ] && echo "pending record: STILL PRESENT" || echo "pending record: absent"
done
