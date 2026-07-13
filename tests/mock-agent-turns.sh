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
  fallback_opencode|fallback_antigravity|skip_failed_primary|distinct_fallback_reviewer|independent_reviewer_unavailable| \
  proto_only_status|proto_only_changed|proto_missing_handoff|proto_missing_next|proto_empty_required_value| \
  proto_invalid_status|proto_duplicate_status|proto_duplicate_handoff|proto_narration_before|proto_narration_after| \
  proto_evidence_omitted|proto_complete|proto_malformed_then_valid|proto_all_malformed| \
  proto_ws_before_space|proto_ws_between_space|proto_ws_after_space|proto_ws_before_tab|proto_ws_between_tab| \
  proto_ws_after_tab|proto_ws_between_mixed|proto_ws_indented_key)
    exit 1
    ;;
  consensus_round2|json_resume|verify_fail_gate|verify_window)
    result='STATUS: PROPOSED
CHANGED: changed.txt
EVIDENCE: mock claude changed
NEXT: codex verifies
HANDOFF: verify this'
    ;;
  judge|judge_noise|judge_clean)
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
  distinct_fallback_reviewer|independent_reviewer_unavailable)
    exit 1
    ;;
esac

case "${MOCK_SCENARIO}" in
  consensus_round2|json_resume|skip_failed_primary)
    if [[ "$count" == "1" ]]; then status="DISAGREE"; else status="VERIFIED"; fi
    ;;
  verify_fail_gate|verify_window)
    status="VERIFIED"
    ;;
  judge|judge_noise|judge_clean)
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
count_file="${MOCK_STATE}/opencode-count"
count=0
[[ -f "$count_file" ]] && count="$(cat "$count_file")"
count=$((count + 1))
echo "$count" > "$count_file"
printf '%s\n' "$*" >> "${MOCK_STATE}/opencode-args.log"
if [[ "${MOCK_SCENARIO}" == "fallback_antigravity" ]]; then
  exit 1
fi
case "${MOCK_SCENARIO}" in
  judge_noise)
    printf 'noise line 1\nnoise line 2\nnoise line 3\nSTATUS: VERIFIED\nHANDOFF: judge says revise\nVERDICT: REQUEST_REVISION\n'
    ;;
  proto_only_status|proto_malformed_then_valid|proto_all_malformed)
    printf 'STATUS: VERIFIED\n'
    ;;
  proto_only_changed)
    printf 'CHANGED: none\n'
    ;;
  proto_missing_handoff)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\n'
    ;;
  proto_missing_next)
    printf 'STATUS: PROPOSED\nCHANGED: none\nHANDOFF: done\n'
    ;;
  proto_empty_required_value)
    printf 'STATUS:\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_invalid_status)
    printf 'STATUS: SUCCESS\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_duplicate_status)
    printf 'STATUS: PROPOSED\nSTATUS: VERIFIED\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_duplicate_handoff)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\nHANDOFF: done again\n'
    ;;
  proto_narration_before)
    printf 'Hey, quick update:\nSTATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_narration_after)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\nThanks for reading!\n'
    ;;
  proto_evidence_omitted)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: fallback response ready\n'
    ;;
  proto_complete)
    printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock complete evidence\nNEXT: none\nHANDOFF: fallback response ready\n'
    ;;
  proto_ws_before_space)
    printf ' \nSTATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\nNEXT: none\nHANDOFF: complete\n'
    ;;
  proto_ws_between_space)
    printf 'STATUS: VERIFIED\nCHANGED: none\n   \nEVIDENCE: mock evidence\nNEXT: none\nHANDOFF: complete\n'
    ;;
  proto_ws_after_space)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\nNEXT: none\nHANDOFF: complete\n  \n'
    ;;
  proto_ws_before_tab)
    printf '\t\nSTATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\nNEXT: none\nHANDOFF: complete\n'
    ;;
  proto_ws_between_tab)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\n\t\nNEXT: none\nHANDOFF: complete\n'
    ;;
  proto_ws_after_tab)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\nNEXT: none\nHANDOFF: complete\n\t\n'
    ;;
  proto_ws_between_mixed)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\n \t \nNEXT: none\nHANDOFF: complete\n'
    ;;
  proto_ws_indented_key)
    printf '  STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\nNEXT: none\nHANDOFF: complete\n'
    ;;
  judge_clean)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: clean mock judge\nNEXT: apply accepted proposal\nHANDOFF: clean judge verdict issued\nVERDICT: ACCEPT_CLAUDE\n'
    ;;
  *)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock judge\nNEXT: none\nHANDOFF: verdict issued\n'
    ;;
esac
EOF

cat > "$mockbin/agy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count_file="${MOCK_STATE}/agy-count"
count=0
[[ -f "$count_file" ]] && count="$(cat "$count_file")"
count=$((count + 1))
echo "$count" > "$count_file"
printf '%s\n' "$*" >> "${MOCK_STATE}/agy-args.log"
case "${MOCK_SCENARIO:-}" in
  distinct_fallback_reviewer)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock agy independent review\nNEXT: none\nHANDOFF: reviewed independently as a distinct provider\n'
    ;;
  proto_only_status|proto_all_malformed)
    printf 'STATUS: VERIFIED\n'
    ;;
  proto_only_changed)
    printf 'CHANGED: none\n'
    ;;
  proto_missing_handoff)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\n'
    ;;
  proto_missing_next)
    printf 'STATUS: PROPOSED\nCHANGED: none\nHANDOFF: done\n'
    ;;
  proto_empty_required_value)
    printf 'STATUS:\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_invalid_status)
    printf 'STATUS: SUCCESS\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_duplicate_status)
    printf 'STATUS: PROPOSED\nSTATUS: VERIFIED\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_duplicate_handoff)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\nHANDOFF: done again\n'
    ;;
  proto_narration_before)
    printf 'Hey, quick update:\nSTATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\n'
    ;;
  proto_narration_after)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\nThanks for reading!\n'
    ;;
  proto_malformed_then_valid)
    printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock agy second fallback\nNEXT: none\nHANDOFF: valid second fallback response\n'
    ;;
  proto_ws_indented_key)
    printf '  STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock evidence\nNEXT: none\nHANDOFF: complete\n'
    ;;
  *)
    printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock agy fallback\nNEXT: codex verifies\nHANDOFF: fallback response ready\n'
    ;;
esac
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

# ask-antigravity: shared skill dir is only passed to agy when it exists.
skill_dir_present="$tmp_root/skill-dir-present"
skill_dir_absent="$tmp_root/skill-dir-absent"
mkdir -p "$skill_dir_present/state" "$skill_dir_absent/state"
prompt_file="$tmp_root/antigravity-prompt.md"
printf 'GOAL: mock\n' > "$prompt_file"

HOME="$skill_dir_present" MOCK_STATE="$skill_dir_present/state" PATH="$mockbin:$PATH" \
  bash -c 'mkdir -p "$HOME/.local/share/agent-bridge" && "$0" "$1" "$2" "$3"' \
  "$repo_dir/bin/ask-antigravity" "$workspace" "$prompt_file" "$skill_dir_present/out.md"
assert_contains "$skill_dir_present/state/agy-args.log" "--add-dir $skill_dir_present/.local/share/agent-bridge"

HOME="$skill_dir_absent" MOCK_STATE="$skill_dir_absent/state" PATH="$mockbin:$PATH" \
  "$repo_dir/bin/ask-antigravity" "$workspace" "$prompt_file" "$skill_dir_absent/out.md"
agy_args="$(cat "$skill_dir_absent/state/agy-args.log")"
[[ "$agy_args" != *"$skill_dir_absent/.local/share/agent-bridge"* ]] || {
  echo "expected no --add-dir for missing skill dir, got: $agy_args" >&2
  exit 1
}

# P0 regression: implementer provider must never also serve as reviewer in
# the same round. Claude and Codex both fail; OpenCode fills in as the
# fallback implementer; OpenCode must be excluded from reviewer fallback
# selection so a distinct provider (agy) performs the independent review.
state="$(MOCK_SCENARIO=distinct_fallback_reviewer AGENT_BRIDGE_RESUME=0 run_case distinct_fallback_reviewer "$repo_dir/bin/agent-turns" "$workspace" "mock distinct fallback reviewer" 1)"
assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_contains "$state/stdout.log" "fallback: agy answered for Codex reviewer"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
opencode_calls="$(cat "$state/opencode-count")"
agy_calls="$(cat "$state/agy-count")"
[[ "$opencode_calls" == "1" ]] || { echo "expected opencode invoked exactly once, got $opencode_calls" >&2; exit 1; }
[[ "$agy_calls" == "1" ]] || { echo "expected agy invoked exactly once, got $agy_calls" >&2; exit 1; }

# P0 regression: when the only configured fallback already served as
# implementer, no distinct reviewer identity remains. The orchestrator must
# fail closed instead of accepting the implementer's own provider as the
# reviewer.
state="$(MOCK_SCENARIO=independent_reviewer_unavailable AGENT_BRIDGE_RESUME=0 AGENT_BRIDGE_FALLBACKS=opencode run_case independent_reviewer_unavailable "$repo_dir/bin/agent-turns" "$workspace" "mock independent reviewer unavailable" 1)"
assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_contains "$state/stdout.log" "independent reviewer unavailable"
if grep -Fq -- "=== Done: CONSENSUS ===" "$state/stdout.log"; then
  echo "expected no CONSENSUS terminal state, but found one" >&2
  cat "$state/stdout.log" >&2
  exit 1
fi
opencode_calls="$(cat "$state/opencode-count")"
[[ "$opencode_calls" == "1" ]] || { echo "expected opencode invoked exactly once, got $opencode_calls" >&2; exit 1; }

assert_not_contains() {
  local file="$1" pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    echo "unexpected pattern found: $pattern" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

# --- Strict turn protocol validation (P1 fix) ---------------------------
# Primary Claude/Codex are made to fail so every case below exercises
# call_fallback's acceptance check directly. Both opencode and agy (the
# default AGENT_BRIDGE_FALLBACKS chain) return the same malformed body for
# the pure-rejection cases so the outcome is deterministic regardless of
# fallback order: neither provider's malformed output may be accepted, both
# get marked unavailable, and the run must fail closed (no CONSENSUS).
for proto_case in \
  proto_only_status proto_only_changed proto_missing_handoff proto_missing_next \
  proto_empty_required_value proto_invalid_status proto_duplicate_status \
  proto_duplicate_handoff proto_narration_before proto_narration_after
do
  state="$(MOCK_SCENARIO="$proto_case" AGENT_BRIDGE_RESUME=0 run_case "$proto_case" "$repo_dir/bin/agent-turns" "$workspace" "mock $proto_case" 1)"
  assert_not_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
  assert_not_contains "$state/stdout.log" "fallback: agy answered for Claude implementer"
  assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
  assert_contains "$state/stderr.log" "provider unavailable for this session: agy"
  assert_contains "$state/stdout.log" "=== Done: CLAUDE_ERROR ==="
  assert_not_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
done

# EVIDENCE is optional: a complete protocol response missing EVIDENCE must
# still be accepted.
state="$(MOCK_SCENARIO=proto_evidence_omitted AGENT_BRIDGE_RESUME=0 run_case proto_evidence_omitted "$repo_dir/bin/agent-turns" "$workspace" "mock proto_evidence_omitted" 1)"
assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="

# Fully complete protocol (all five fields, EVIDENCE included once) must be
# accepted.
state="$(MOCK_SCENARIO=proto_complete AGENT_BRIDGE_RESUME=0 run_case proto_complete "$repo_dir/bin/agent-turns" "$workspace" "mock proto_complete" 1)"
assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="

# First fallback (opencode) returns a malformed/partial protocol and must be
# marked unavailable; the chain must proceed to the next fallback (agy),
# whose complete valid protocol is accepted and the run continues normally.
state="$(MOCK_SCENARIO=proto_malformed_then_valid AGENT_BRIDGE_RESUME=0 run_case proto_malformed_then_valid "$repo_dir/bin/agent-turns" "$workspace" "mock proto_malformed_then_valid" 1)"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_not_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_contains "$state/stdout.log" "fallback: agy answered for Claude implementer"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="

# Every configured fallback returns a malformed/partial protocol: no
# malformed response may be accepted, no CONSENSUS may be emitted, and the
# run must terminate in a deterministic non-success state.
state="$(MOCK_SCENARIO=proto_all_malformed AGENT_BRIDGE_RESUME=0 run_case proto_all_malformed "$repo_dir/bin/agent-turns" "$workspace" "mock proto_all_malformed" 1)"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stderr.log" "provider unavailable for this session: agy"
assert_contains "$state/stdout.log" "=== Done: CLAUDE_ERROR ==="
assert_not_contains "$state/stdout.log" "=== Done: CONSENSUS ==="

# --- Whitespace-only lines must be tolerated like blank lines (P2 fix) ---
# A structurally valid protocol response must be accepted regardless of
# spaces-only, tabs-only, or mixed-whitespace-only lines appearing before,
# between, or after the protocol fields.
for proto_case in \
  proto_ws_before_space proto_ws_between_space proto_ws_after_space \
  proto_ws_before_tab proto_ws_between_tab proto_ws_after_tab \
  proto_ws_between_mixed
do
  state="$(MOCK_SCENARIO="$proto_case" AGENT_BRIDGE_RESUME=0 run_case "$proto_case" "$repo_dir/bin/agent-turns" "$workspace" "mock $proto_case" 1)"
  assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
  assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
done

# Leading whitespace/indentation before a protocol key must NOT be trimmed
# away — an indented "  STATUS: VERIFIED" line is not a recognized field
# line and must still be rejected, same as any other narration line.
state="$(MOCK_SCENARIO=proto_ws_indented_key AGENT_BRIDGE_RESUME=0 run_case proto_ws_indented_key "$repo_dir/bin/agent-turns" "$workspace" "mock proto_ws_indented_key" 1)"
assert_not_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_not_contains "$state/stdout.log" "fallback: agy answered for Claude implementer"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stderr.log" "provider unavailable for this session: agy"
assert_contains "$state/stdout.log" "=== Done: CLAUDE_ERROR ==="
assert_not_contains "$state/stdout.log" "=== Done: CONSENSUS ==="

# --- Clean judge scenario: a properly anchored VERDICT line in a genuine
# judge response must reach the next agent prompt (P2 fix). Claude and
# Codex both DISAGREE, forcing escalation to the OpenCode judge, whose
# response here is a clean, complete protocol block with a VERDICT line
# (distinct from judge_noise, which exercises narration tolerance).
state="$(MOCK_SCENARIO=judge_clean run_case judge_clean "$repo_dir/bin/agent-turns" "$workspace" "mock judge clean" 2)"
assert_contains "$state/stdout.log" "escalating to OpenCode judge"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
# Judge escalation actually occurred: the raw judge artifact was produced.
[[ -s "$judge_run_dir/round-1-judge.out.md" ]] || {
  echo "expected judge artifact round-1-judge.out.md to exist" >&2
  exit 1
}
# The anchored VERDICT line exists verbatim in the judge's own output.
grep -q '^VERDICT: ACCEPT_CLAUDE$' "$judge_run_dir/round-1-judge.out.md" || {
  echo "expected anchored VERDICT: ACCEPT_CLAUDE line in judge artifact" >&2
  cat "$judge_run_dir/round-1-judge.out.md" >&2
  exit 1
}
# The verdict propagates into the next agent's (round 2 Claude) prompt.
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "VERDICT: ACCEPT_CLAUDE"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "clean judge verdict issued"

echo "mock-agent-turns: ok"
