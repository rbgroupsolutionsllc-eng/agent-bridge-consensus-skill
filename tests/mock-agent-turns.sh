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
next=0
for arg in "$@"; do
  [[ "$arg" == "--output-format" ]] && next=1 && continue
  if [[ "$next" == "1" ]]; then
    [[ "$arg" == "json" ]] && json=1
    next=0
  fi
done

if [[ "$json" == "1" && "${MOCK_SCENARIO}" == "claude_bad_json" ]]; then
  printf '{not-json\n'
  exit 0
fi

case "${MOCK_SCENARIO}" in
  fallback_opencode|fallback_antigravity|skip_failed_primary)
    exit 1
    ;;
  consensus_round2|json_resume|verify_fail_gate|verify_window)
    result='STATUS: PROPOSED
CHANGED: changed.txt
EVIDENCE: mock claude changed
NEXT: codex verifies
HANDOFF: verify this'
    ;;
  judge|judge_noise)
    result='STATUS: DISAGREE
CHANGED: none
EVIDENCE: claude disagrees
NEXT: judge if codex disagrees
HANDOFF: dispute remains'
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

if [[ "${1:-}" == "exec" && "${2:-}" == "resume" && "${3:-}" == "--help" ]]; then
  [[ "${MOCK_CODEX_RESUME_SUPPORT:-0}" == "1" ]] && exit 0
  exit 1
fi

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
  consensus_round2|json_resume|skip_failed_primary)
    if [[ "$count" == "1" ]]; then status="DISAGREE"; else status="VERIFIED"; fi
    ;;
  verify_fail_gate|verify_window)
    status="VERIFIED"
    ;;
  judge|judge_noise)
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
printf '%s\n' "$*" >> "${MOCK_STATE}/opencode-args.log"
if [[ "${MOCK_SCENARIO}" == "fallback_antigravity" ]]; then
  exit 1
fi
if [[ "${MOCK_SCENARIO}" == "judge_noise" ]]; then
  printf 'noise line 1\nnoise line 2\nnoise line 3\nSTATUS: VERIFIED\nHANDOFF: judge says revise\nVERDICT: REQUEST_REVISION\n'
else
  printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock judge\nNEXT: none\nHANDOFF: verdict issued\nVERDICT: ACCEPT_CLAUDE\n'
fi
EOF

cat > "$mockbin/agy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${MOCK_STATE}/agy-args.log"
printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock agy fallback\nNEXT: codex verifies\nHANDOFF: fallback response ready\n'
EOF

cat > "$mockbin/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-r" ]]; then
  query="$2"
  file="$3"
else
  query="$1"
  file="$2"
fi
python3 - "$query" "$file" <<'PY'
import json, sys
query, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
if query in (".result", ".result // empty"):
    print(data.get("result", ""))
elif query == ".session_id // empty":
    print(data.get("session_id", ""))
elif query == ".total_cost_usd // 0":
    print(data.get("total_cost_usd", 0))
else:
    raise SystemExit(f"unsupported jq query: {query}")
PY
EOF

chmod +x "$mockbin/claude" "$mockbin/codex" "$mockbin/opencode" "$mockbin/agy" "$mockbin/jq"

run_case() {
  local name="$1"
  shift
  local state="$tmp_root/state-$name"
  mkdir -p "$state"
  MOCK_STATE="$state" PATH="$mockbin:$PATH" AGENT_BRIDGE_HOME="$bridge_home/$name" "$@" > "$state/stdout.log" 2> "$state/stderr.log"
  echo "$state"
}

run_case_fail() {
  local name="$1"
  shift
  local state="$tmp_root/state-$name"
  mkdir -p "$state"
  set +e
  MOCK_STATE="$state" PATH="$mockbin:$PATH" AGENT_BRIDGE_HOME="$bridge_home/$name" "$@" > "$state/stdout.log" 2> "$state/stderr.log"
  echo "$?" > "$state/exit-code"
  set -e
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

assert_section_count() {
  local file="$1" expected="$2" actual
  actual="$(grep -c '^## ' "$file" || true)"
  [[ "$actual" == "$expected" ]] || {
    echo "expected $expected handoff sections, got $actual" >&2
    cat "$file" >&2
    exit 1
  }
}

state="$(MOCK_SCENARIO=consensus_round2 run_case consensus_round2 "$repo_dir/bin/agent-turns" "$workspace" "mock consensus" 3)"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
assert_contains "$state/stdout.log" 'Total Claude cost: $0.0300'
[[ "$(cat "$state/codex-count")" == "2" ]]

state="$(MOCK_SCENARIO=judge_noise run_case judge_noise "$repo_dir/bin/agent-turns" "$workspace" "mock judge" 2)"
assert_contains "$state/stdout.log" "escalating to OpenCode judge"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "VERDICT: REQUEST_REVISION"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "HANDOFF: judge says revise"

state="$(MOCK_SCENARIO=verify_fail_gate AGENT_BRIDGE_VERIFY_CMD='exit 1' run_case verify_fail_gate "$repo_dir/bin/agent-turns" "$workspace" "mock verify fail" 2)"
assert_contains "$state/stdout.log" "consensus REJECTED: verify failing"
assert_contains "$state/stdout.log" "=== Done: VERIFY_FAILING ==="
assert_contains "$state/stdout.log" "ORCHESTRATOR REJECTED VERIFIED"

state="$(MOCK_SCENARIO=claude_bad_json AGENT_BRIDGE_FALLBACKS=disabled run_case claude_bad_json "$repo_dir/bin/agent-turns" "$workspace" "mock bad json" 2)"
assert_contains "$state/stdout.log" "=== Done: CLAUDE_ERROR ==="
assert_contains "$state/stdout.log" "STATUS: BLOCKED"
assert_contains "$state/stdout.log" "claude returned unparseable/empty JSON"

state="$(MOCK_SCENARIO=verify_window AGENT_BRIDGE_VERIFY_CMD='exit 1' run_case verify_window "$repo_dir/bin/agent-turns" "$workspace" "mock verify window" 4)"
window_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_section_count "$window_run_dir/handoff.md" 4
assert_contains "$window_run_dir/handoff.md" "Round 4 - Claude"
assert_contains "$window_run_dir/handoff.md" "GROUND TRUTH FAILED"
assert_contains "$window_run_dir/handoff.md" "Round 4 - Codex"
assert_contains "$window_run_dir/handoff.md" "ORCHESTRATOR REJECTED"

state="$(MOCK_SCENARIO=preflight AGENT_BRIDGE_CODEX_RESUME=1 run_case_fail preflight "$repo_dir/bin/agent-turns" "$workspace" "mock preflight" 1)"
[[ "$(cat "$state/exit-code")" == "2" ]]
assert_contains "$state/stderr.log" "does not support 'exec resume'"

state="$(MOCK_SCENARIO=json_resume AGENT_BRIDGE_RESUME=1 run_case json_resume "$repo_dir/bin/agent-turns" "$workspace" "mock json resume" 2)"
assert_contains "$state/stdout.log" 'Total Claude cost: $0.0300'
assert_contains "$state/claude-args.log" "--resume sid-1"

state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 run_case fallback_opencode "$repo_dir/bin/agent-turns" "$workspace" "mock opencode fallback" 1)"
assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
assert_contains "$state/opencode-args.log" "--model opencode-go/minimax-m3"

state="$(MOCK_SCENARIO=fallback_antigravity AGENT_BRIDGE_RESUME=0 run_case fallback_antigravity "$repo_dir/bin/agent-turns" "$workspace" "mock antigravity fallback" 1)"
assert_contains "$state/stdout.log" "fallback: opencode unavailable"
assert_contains "$state/stdout.log" "fallback: agy answered for Claude implementer"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
assert_contains "$state/agy-args.log" "--model"

state="$(MOCK_SCENARIO=skip_failed_primary AGENT_BRIDGE_RESUME=0 run_case skip_failed_primary "$repo_dir/bin/agent-turns" "$workspace" "mock failed provider skip" 2)"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
[[ "$(cat "$state/claude-count")" == "1" ]]
[[ "$(cat "$state/codex-count")" == "2" ]]

echo "mock-agent-turns: ok"
