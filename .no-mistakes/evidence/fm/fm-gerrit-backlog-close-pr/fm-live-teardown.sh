#!/usr/bin/env bash
# Live drive: real bin/fm-teardown.sh + real tasks-axi 0.2.6 in a disposable lab home.
set -u
W=${FM_W:-/home/jthien/.no-mistakes/worktrees/153164a827ab/01M3SFAGMMDWD5ETC4XNXZT44N}
PRURL=$1; ID=${2:-task-g1}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/fakebin"
# treehouse would return the worktree to the real pool; stub it (only cleanup plumbing).
printf '#!/usr/bin/env bash\nexit 0\n' > "$LAB/fakebin/treehouse"; chmod +x "$LAB/fakebin/treehouse"
git init -q -b main "$LAB/proj"; git -C "$LAB/proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$LAB/proj" worktree add -q -b "fm/$ID" "$LAB/wt"
printf '%s\n' '# Backlog' '' '## In flight' '' '## Queued' '' '## Done' > "$LAB/data/backlog.md"
tasks-axi add "$ID" "gerrit landing" --kind ship --file "$LAB/data/backlog.md" >/dev/null
tasks-axi start "$ID" --file "$LAB/data/backlog.md" >/dev/null
cat > "$LAB/state/$ID.meta" <<M
window=firstmate:fm-$ID
endpoint_task_id=$ID
worktree=$LAB/wt
project=$LAB/proj
kind=ship
mode=no-mistakes
spawn_gen=live-$ID
pr=$PRURL
M
echo "== before: tasks-axi show $ID"; tasks-axi show "$ID" --file "$LAB/data/backlog.md" | grep -E 'state|links'
echo "== bin/fm-teardown.sh $ID  (FM_HOME=lab, real tasks-axi $(tasks-axi --version))"
cd "$W"
env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
  TMUX_TMPDIR="$LAB/tmux" TMUX= FM_HOME="$LAB" PATH="$LAB/fakebin:$PATH" bin/fm-teardown.sh "$ID" 2>&1; echo "teardown rc=$?"
echo "== after: tasks-axi show $ID --full"; tasks-axi show "$ID" --file "$LAB/data/backlog.md" --full
echo "== pending close record: $(ls "$LAB/state/$ID.backlog-close" 2>/dev/null || echo absent)"
echo "LAB=$LAB"
