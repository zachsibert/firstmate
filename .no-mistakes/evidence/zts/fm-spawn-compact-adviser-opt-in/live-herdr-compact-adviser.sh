#!/usr/bin/env bash
# Live drive: real bin/fm-spawn.sh into an isolated Herdr lab session. The raw
# launch command IS the agent: it records the environment it was started with.
set -u
ROOT=/Users/zachsibert/.no-mistakes/worktrees/100ce640ce38/01M37MJVR6ZBCPAVBDWND06ADM
EVID=/Users/zachsibert/.no-mistakes/evidence/01M37MJVR6ZBCPAVBDWND06ADM
# The lab Herdr server inherits this process environment, and every lab pane
# shell inherits the server, so drop the switch here: the pane must start clean
# for the ambient case to mean anything.
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION TMUX TMUX_PANE COMPACT_ADVISER_DISABLE
LAB="$ROOT/bin/fm-herdr-lab.sh"
SESSION=$("$LAB" name fm-compact-adv) || exit 1
export HERDR_SESSION="$SESSION"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-compact-adviser-live.XXXXXX")
WORKTREES=()
CLEANED=0
cleanup() {
  local status=$? wt
  [ "$CLEANED" = 0 ] || return 0; CLEANED=1
  for wt in ${WORKTREES[@]+"${WORKTREES[@]}"}; do treehouse return --force "$wt" >/dev/null 2>&1; done
  "$LAB" teardown "$SESSION" && echo "lab teardown ok: $SESSION" || { echo "LAB TEARDOWN FAILED"; status=1; }
  rm -rf "$TMP"
  exit "$status"
}
trap cleanup EXIT
"$LAB" provision "$SESSION" || exit 1
echo "lab session: $SESSION"

PROJ="$TMP/project"; mkdir -p "$PROJ"
git -C "$PROJ" init -q && printf '# scratch\n' > "$PROJ/README.md" && git -C "$PROJ" add README.md \
  && git -C "$PROJ" -c user.name=t -c user.email=t@example.invalid commit -qm init
git clone --quiet --bare "$PROJ" "$PROJ.origin.git" && git -C "$PROJ" remote add origin "file://$PROJ.origin.git"

make_home() { # <name> <compact-adviser:absent|present> <allowlist:absent|enabled|listed>
  local h="$TMP/home-$1"
  mkdir -p "$h/state" "$h/config" "$h/data/$1"
  printf 'off\n' > "$h/config/herdr-presentation-spaces"
  [ "$2" = present ] && : > "$h/config/compact-adviser"
  case $3 in
    enabled) : > "$h/config/launch-env-allowlist" ;;
    listed) printf '%s\n' TYPESAFE_API_KEY CLAUDE_CODE_ENABLE_FUNCTION_HOOKS > "$h/config/launch-env-allowlist" ;;
  esac
  printf '# Task\n## Captain'"'"'s intent\nlive compact-adviser check %s\n\n## Firstmate spec\nrecord env.\n' "$1" > "$h/data/$1/brief.md"
  printf '%s' "$h"
}

# The "agent": prints the three variables the change governs into a file.
drive() { # <id> <compact-adviser> <allowlist>
  local id=$1 home out rc meta wt pane i probe="$TMP/$1.env"
  home=$(make_home "$id" "$2" "$3")
  cat > "$TMP/$id.probe.sh" <<'PROBE'
#!/bin/sh
# The agent under test. Reports presence only for the key: the lab pane shell
# loads the captain's real key from its own rc files, and a value must never
# reach the evidence log.
out=$1
if [ -n "${TYPESAFE_API_KEY+x}" ]; then key="set(len=${#TYPESAFE_API_KEY})"; else key=unset; fi
printf 'COMPACT_ADVISER_DISABLE=%s\nTYPESAFE_API_KEY=%s\nCLAUDE_CODE_ENABLE_FUNCTION_HOOKS=%s\n' \
  "${COMPACT_ADVISER_DISABLE-unset}" "$key" "${CLAUDE_CODE_ENABLE_FUNCTION_HOOKS-unset}" > "$out"
sleep 600
PROBE
  local launch="sh $TMP/$id.probe.sh $probe"
  out=$(env -u HERDR_ENV -u HERDR_PANE_ID HERDR_SESSION="$SESSION" FM_SPAWN_NO_GUARD=1 FM_GATE_REFUSE_BYPASS=1 FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    TYPESAFE_API_KEY=spawn-process-value-must-not-leak CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 \
    "$ROOT/bin/fm-spawn.sh" "$id" "$PROJ" "$launch" --mode no-mistakes --yolo off --backend herdr 2>&1); rc=$?
  echo "== $id (compact-adviser=$2 allowlist=$3) spawn rc=$rc"
  [ "$rc" -eq 0 ] || { echo "$out" | tail -20; return 1; }
  meta="$home/state/$id.meta"
  wt=$(grep '^worktree=' "$meta" | cut -d= -f2-); [ -n "$wt" ] && WORKTREES+=("$wt")
  pane=$(grep '^herdr_pane_id=' "$meta" | cut -d= -f2-)
  echo "   herdr pane: $pane"
  i=0; while [ ! -s "$probe" ] && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
  [ -s "$probe" ] || { echo "   agent never wrote its environment"; "$LAB" run "$SESSION" pane get "$pane" | head -c 600; return 1; }
  echo "   agent saw:"; sed 's/^/     /' "$probe"
  # Also show what the real pane screen holds (the launch text the pane ran).
    grep -q 'len=32)' "$probe" && echo "   LEAK: spawning process value reached the agent"
  return 0
}

drive default-ambient  absent  absent
drive default-allow    absent  enabled
drive optin-ambient    present absent
drive optin-allow-empty present enabled
drive optin-allow-listed present listed
