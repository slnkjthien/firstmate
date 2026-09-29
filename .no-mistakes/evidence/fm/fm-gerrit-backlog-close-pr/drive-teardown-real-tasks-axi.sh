#!/usr/bin/env bash
# Drive bin/fm-teardown.sh from the checkout given as $1 against the REAL
# installed tasks-axi (no wrapper), for a Gerrit and a GitHub landed ship,
# plus a session-start replay of a pre-fix pending close record.
set -u
CHECKOUT=$1
cd "$CHECKOUT"
cut=$(awk '/^test_[a-z_0-9]+$/{print NR-1; exit}' tests/fm-teardown.test.sh); defs=$(mktemp); head -n "$cut" tests/fm-teardown.test.sh | sed "s#\$(dirname \"\${BASH_SOURCE\[0\]}\")#$CHECKOUT/tests#g" > "$defs"
. "$defs"; rm -f "$defs"
echo "tasks-axi $(tasks-axi --version) at $(command -v tasks-axi)"
echo "checkout HEAD: $(git -C "$CHECKOUT" rev-parse --short HEAD)"
for spec in "gerrit https://gerrit.example.com/c/project/+/12345" "github https://github.com/example/repo/pull/7"; do
  set -- $spec; name=$1 url=$2
  case_dir=$(make_case live-$name)
  write_meta "$case_dir" no-mistakes ship
  printf 'pr=%s\n' "$url" >> "$case_dir/state/task-x1.meta"
  seed_backlog_in_flight "$case_dir"
  echo; echo "=== $name landed ship: pr=$url"
  out=$(run_teardown "$case_dir" 2>&1); rc=$?
  echo "teardown rc=$rc"; printf '%s\n' "$out" | grep -iE 'backlog|tasks-axi|canonical|error' | head -8
  echo "--- tasks-axi show task-x1 --full"
  tasks-axi show task-x1 --file "$case_dir/data/backlog.md" --full | grep -E 'state:|links:|body:|pr'
  if [ -e "$case_dir/state/task-x1.backlog-close" ]; then echo "pending close record LEFT:"; cat "$case_dir/state/task-x1.backlog-close"; else echo "pending close record: absent"; fi
done
