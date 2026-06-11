#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

mockbin="$tmp_root/bin"
workspace="$tmp_root/workspace"
bridge_home="$tmp_root/bridge"
mkdir -p "$mockbin" "$workspace" "$bridge_home"

cat > "$mockbin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

count_file="${MOCK_STATE}/claude-count"
count=0
[[ -f "$count_file" ]] && count="$(cat "$count_file")"
count=$((count + 1))
echo "$count" > "$count_file"
printf 'call%d %s\n' "$count" "$*" >> "${MOCK_STATE}/claude-args.log"

json=0
for arg in "$@"; do
  [[ "$arg" == "--output-format" ]] && next=1 && continue
  if [[ "${next:-0}" == "1" ]]; then
    [[ "$arg" == "json" ]] && json=1
    next=0
  fi
done

case "${MOCK_SCENARIO}" in
  consensus_round2)
    result='STATUS: PROPOSED
CHANGED: changed.txt
EVIDENCE: mock claude
NEXT: codex verifies
HANDOFF: verify this'
    ;;
  verify_exit)
    result='STATUS: PROPOSED
CHANGED: changed.txt
EVIDENCE: mock changed
NEXT: codex verifies
HANDOFF: verify ground truth'
    ;;
  judge)
    result='STATUS: DISAGREE
CHANGED: none
EVIDENCE: claude disagrees
NEXT: judge if codex disagrees
HANDOFF: dispute remains'
    ;;
  json_resume)
    result='STATUS: PROPOSED
CHANGED: none
EVIDENCE: json resume mock
NEXT: codex verifies
HANDOFF: continue'
    ;;
  *)
    result='STATUS: PROPOSED
CHANGED: none
EVIDENCE: default
NEXT: none
HANDOFF: default'
    ;;
esac

if [[ "$json" == "1" ]]; then
  cost="0.0100"
  [[ "$count" == "2" ]] && cost="0.0200"
  printf '{"result":%s,"session_id":"sid-1","total_cost_usd":%s}\n' "$(RESULT="$result" python3 -c 'import json,os; print(json.dumps(os.environ["RESULT"]))')" "$cost"
else
  printf '%s\n' "$result"
fi
EOF

cat > "$mockbin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

count_file="${MOCK_STATE}/codex-count"
count=0
[[ -f "$count_file" ]] && count="$(cat "$count_file")"
count=$((count + 1))
echo "$count" > "$count_file"
printf 'call%d %s\n' "$count" "$*" >> "${MOCK_STATE}/codex-args.log"

out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--output-last-message" ]]; then
    out="$arg"
    break
  fi
  prev="$arg"
done
[[ -n "$out" ]] || { echo "missing --output-last-message" >&2; exit 2; }

case "${MOCK_SCENARIO}" in
  consensus_round2)
    if [[ "$count" == "1" ]]; then status="DISAGREE"; else status="VERIFIED"; fi
    ;;
  verify_exit)
    status="VERIFIED"
    ;;
  judge)
    if [[ "$count" == "1" ]]; then status="DISAGREE"; else status="VERIFIED"; fi
    ;;
  json_resume)
    if [[ "$count" == "1" ]]; then status="DISAGREE"; else status="VERIFIED"; fi
    ;;
  *)
    status="VERIFIED"
    ;;
esac

cat > "$out" <<EOM
STATUS: $status
CHANGED: none
EVIDENCE: mock codex $count
NEXT: none
HANDOFF: mock handoff
EOM
EOF

cat > "$mockbin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock judge\nNEXT: none\nHANDOFF: verdict issued\nVERDICT: ACCEPT_CLAUDE\n'
EOF

cat > "$mockbin/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
query="$2"
file="$3"
python3 - "$query" "$file" <<'PY'
import json, sys
query, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
if query == ".result":
    print(data.get("result", ""))
elif query == ".session_id // empty":
    print(data.get("session_id", ""))
elif query == ".total_cost_usd // 0":
    print(data.get("total_cost_usd", 0))
else:
    raise SystemExit(f"unsupported jq query: {query}")
PY
EOF

chmod +x "$mockbin/claude" "$mockbin/codex" "$mockbin/opencode" "$mockbin/jq"

run_case() {
  local name="$1"
  shift
  local state="$tmp_root/state-$name"
  mkdir -p "$state"
  MOCK_STATE="$state" PATH="$mockbin:$PATH" AGENT_BRIDGE_HOME="$bridge_home/$name" "$@" > "$state/stdout.log" 2> "$state/stderr.log"
  echo "$state"
}

assert_contains() {
  local file="$1" pattern="$2"
  grep -Fq -- "$pattern" "$file" || {
    echo "expected pattern not found: $pattern" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    local err="${file%/*}/stderr.log"
    if [[ -f "$err" ]]; then
      echo "--- $err ---" >&2
      cat "$err" >&2
    fi
    exit 1
  }
}

state="$(MOCK_SCENARIO=consensus_round2 run_case consensus_round2 "$repo_dir/bin/agent-turns" "$workspace" "mock consensus" 3)"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
[[ "$(cat "$state/codex-count")" == "2" ]]

state="$(MOCK_SCENARIO=verify_exit AGENT_BRIDGE_VERIFY_CMD='exit 7' run_case verify_exit "$repo_dir/bin/agent-turns" "$workspace" "mock verify" 2)"
assert_contains "$state/stdout.log" "verify: exit=7"
assert_contains "$state/stdout.log" 'GROUND TRUTH after claude'

state="$(MOCK_SCENARIO=judge run_case judge "$repo_dir/bin/agent-turns" "$workspace" "mock judge" 2)"
assert_contains "$state/stdout.log" "escalating to OpenCode judge"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "JUDGE VERDICT"

state="$(MOCK_SCENARIO=json_resume AGENT_BRIDGE_RESUME=1 run_case json_resume "$repo_dir/bin/agent-turns" "$workspace" "mock json resume" 2)"
assert_contains "$state/stdout.log" 'Total Claude cost: $0.0300'
assert_contains "$state/claude-args.log" "--resume sid-1"

echo "mock-agent-turns: ok"
