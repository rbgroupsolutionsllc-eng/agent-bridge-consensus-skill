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
  proto_ws_after_tab|proto_ws_between_mixed|proto_ws_indented_key|proto_verdict_line)
    exit 1
    ;;
  consensus_round2|json_resume|verify_fail_gate|verify_window)
    result='STATUS: PROPOSED
CHANGED: changed.txt
EVIDENCE: mock claude changed
NEXT: codex verifies
HANDOFF: verify this'
    ;;
  judge|judge_noise|judge_clean|judgeproto_*)
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
  judge|judge_noise|judge_clean|judgeproto_*)
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
  proto_verdict_line)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\nVERDICT: ACCEPT_CLAUDE\n'
    ;;
  judge_clean)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: clean mock judge\nNEXT: apply accepted proposal\nHANDOFF: clean judge verdict issued\nVERDICT: ACCEPT_CLAUDE\n'
    ;;
  judgeproto_*)
    if [[ -n "${MOCK_JUDGE_BODY_OPENCODE:-}" && -f "${MOCK_JUDGE_BODY_OPENCODE:-}" ]]; then
      cat "$MOCK_JUDGE_BODY_OPENCODE"
    fi
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
  proto_verdict_line)
    printf 'STATUS: PROPOSED\nCHANGED: none\nNEXT: none\nHANDOFF: done\nVERDICT: ACCEPT_CLAUDE\n'
    ;;
  judge_noise)
    # OpenCode's decoy/noise output is invalid and rejected; agy is the
    # distinct fallback judge that returns a complete, valid protocol with a
    # real anchored VERDICT line.
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock agy judge\nNEXT: none\nHANDOFF: judge says revise\nVERDICT: REQUEST_REVISION\n'
    ;;
  judgeproto_*)
    if [[ -n "${MOCK_JUDGE_BODY_AGY:-}" && -f "${MOCK_JUDGE_BODY_AGY:-}" ]]; then
      cat "$MOCK_JUDGE_BODY_AGY"
    fi
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

assert_not_contains() {
  local file="$1" pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    echo "unexpected pattern found: $pattern" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

state="$(MOCK_SCENARIO=consensus_round2 run_case consensus_round2 "$repo_dir/bin/agent-turns" "$workspace" "mock consensus" 3)"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
assert_contains "$state/stdout.log" 'Total Claude cost: $0.0300'
[[ "$(cat "$state/codex-count")" == "2" ]]

state="$(MOCK_SCENARIO=judge_noise run_case judge_noise "$repo_dir/bin/agent-turns" "$workspace" "mock judge" 2)"
assert_contains "$state/stdout.log" "escalating to OpenCode judge"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
# OpenCode's decoy narration (STATUS anchored, no VERDICT, narration lines,
# missing CHANGED/NEXT) is structurally invalid and must be rejected, not
# accepted merely because a STATUS: line exists somewhere in the text.
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stdout.log" "judge: OpenCode unavailable, trying agy"
# agy is the distinct fallback judge and its real, anchored VERDICT
# propagates into the next round's prompt.
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "VERDICT: REQUEST_REVISION"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "HANDOFF: judge says revise"
# The decoy "ACCEPT_CODEX" narration from OpenCode's rejected output must
# never surface as a verdict token in the propagated prompt.
assert_not_contains "$judge_run_dir/round-2-claude.prompt.md" "ACCEPT_CODEX"

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

write_judge_body() {
  local path="$1"
  shift
  printf '%s\n' "$@" > "$path"
}

judge_count=0
run_judge_case() {
  # run_judge_case <name> <opencode-body-file-or-empty> <agy-body-file-or-empty> <rounds>
  # Default rounds=1: with only one round, the judge note is always among
  # the last two handoff sections (never evicted by trim_handoff), so
  # handoff.md reliably reflects the judge outcome at run end. Tests that
  # need to see propagation into a SUBSEQUENT round's prompt pass rounds=2
  # explicitly and assert against the round-2 prompt file instead (built
  # before that round's own trims run).
  local name="$1" rounds="${4:-1}"
  judge_count=$((judge_count + 1))
  MOCK_SCENARIO="judgeproto_$name" MOCK_JUDGE_BODY_OPENCODE="$2" MOCK_JUDGE_BODY_AGY="$3" \
    run_case "judgeproto_$name" "$repo_dir/bin/agent-turns" "$workspace" "mock judgeproto $name" "$rounds"
}

# ==========================================================================
# STRICT JUDGE VERDICT VALIDATION (P1 fix)
#
# A judge response is accepted only when it satisfies the complete judge
# protocol: STATUS/CHANGED/NEXT/HANDOFF/VERDICT exactly once each, EVIDENCE
# 0-1 times, allowed STATUS/VERDICT enums, no narration/unknown lines, no
# Markdown fences. Verdict tokens appearing in narration or other fields
# must never be picked up as the verdict. Applies uniformly to the OpenCode
# primary judge and the agy fallback judge.
# ==========================================================================

# --- RED regression: decoy narration without an anchored VERDICT line must
# never manufacture a false verdict (this exact case was PROVEN to leak
# "VERDICT: ACCEPT_CODEX" into the next round's prompt before this fix,
# via the pre-fix whole-file token search in judge_summary combined with the
# pre-fix acceptance check that only required an anchored STATUS: or
# VERDICT: line ANYWHERE).
decoy_no_verdict_body="$tmp_root/judgeproto-decoy-no-verdict.md"
write_judge_body "$decoy_no_verdict_body" \
  'STATUS: VERIFIED' \
  'CHANGED: none' \
  'EVIDENCE: ACCEPT_CODEX was considered but rejected' \
  'NEXT: none' \
  'HANDOFF: judge reviewed both proposals'
state="$(run_judge_case decoy_narration_no_verdict "$decoy_no_verdict_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stderr.log" "provider unavailable for this session: agy"
[[ ! -e "$judge_run_dir/round-1-judge.out.md" ]] || {
  echo "expected invalid judge artifact to be removed, but it survived" >&2
  exit 1
}
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
assert_not_contains "$judge_run_dir/handoff.md" "ACCEPT_CODEX"

# --- Incomplete protocol shapes must all be rejected ---------------------
judge_status_only_body="$tmp_root/judgeproto-status-only.md"
write_judge_body "$judge_status_only_body" 'STATUS: VERIFIED'
state="$(run_judge_case status_only "$judge_status_only_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

judge_verdict_only_body="$tmp_root/judgeproto-verdict-only.md"
write_judge_body "$judge_verdict_only_body" 'VERDICT: ACCEPT_CLAUDE'
state="$(run_judge_case verdict_only "$judge_verdict_only_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

judge_empty_verdict_body="$tmp_root/judgeproto-empty-verdict.md"
write_judge_body "$judge_empty_verdict_body" \
  'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' 'VERDICT:'
state="$(run_judge_case empty_verdict "$judge_empty_verdict_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

judge_ws_verdict_body="$tmp_root/judgeproto-ws-verdict.md"
write_judge_body "$judge_ws_verdict_body" \
  'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' 'VERDICT:    '
state="$(run_judge_case whitespace_verdict "$judge_ws_verdict_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

# --- Invalid VERDICT tokens (enum enforcement) ---------------------------
invalid_verdict_idx=0
for bad_token in "ACCEPT_BOTH" "SUCCESS" "VERIFIED" "1"; do
  invalid_verdict_idx=$((invalid_verdict_idx + 1))
  body="$tmp_root/judgeproto-invalid-verdict-$invalid_verdict_idx.md"
  write_judge_body "$body" \
    'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' "VERDICT: $bad_token"
  state="$(run_judge_case "invalid_verdict_$invalid_verdict_idx" "$body" "")"
  judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
  assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
  assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
done

# --- Case sensitivity: lowercase verdict rejected -------------------------
judge_lowercase_body="$tmp_root/judgeproto-lowercase.md"
write_judge_body "$judge_lowercase_body" \
  'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' 'VERDICT: accept_claude'
state="$(run_judge_case lowercase_verdict "$judge_lowercase_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

# --- Extended/trailing-content verdict lines rejected ---------------------
extended_idx=0
for bad_line in "VERDICT: ACCEPT_CLAUDE extra" "VERDICT: ACCEPT_CLAUDE:" "VERDICT: ACCEPT_CLAUDE REQUEST_REVISION"; do
  extended_idx=$((extended_idx + 1))
  body="$tmp_root/judgeproto-extended-$extended_idx.md"
  write_judge_body "$body" 'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' "$bad_line"
  state="$(run_judge_case "extended_verdict_$extended_idx" "$body" "")"
  judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
  assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
  assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
done

# --- Duplicate VERDICT line rejected --------------------------------------
judge_dup_verdict_body="$tmp_root/judgeproto-dup-verdict.md"
write_judge_body "$judge_dup_verdict_body" \
  'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' \
  'VERDICT: ACCEPT_CLAUDE' 'VERDICT: ACCEPT_CODEX'
state="$(run_judge_case duplicate_verdict "$judge_dup_verdict_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

# --- Decoy token in EVIDENCE (no VERDICT line) rejected -------------------
judge_decoy_evidence_body="$tmp_root/judgeproto-decoy-evidence.md"
write_judge_body "$judge_decoy_evidence_body" \
  'STATUS: VERIFIED' 'CHANGED: none' \
  'EVIDENCE: ACCEPT_CODEX appeared in a prior proposal' \
  'NEXT: none' 'HANDOFF: done'
state="$(run_judge_case decoy_in_evidence "$judge_decoy_evidence_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
assert_not_contains "$judge_run_dir/handoff.md" "ACCEPT_CODEX"

# --- Decoy token in HANDOFF (no VERDICT line) rejected ---------------------
judge_decoy_handoff_body="$tmp_root/judgeproto-decoy-handoff.md"
write_judge_body "$judge_decoy_handoff_body" \
  'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' \
  'HANDOFF: do not use ACCEPT_CLAUDE yet'
state="$(run_judge_case decoy_in_handoff "$judge_decoy_handoff_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
assert_not_contains "$judge_run_dir/handoff.md" "VERDICT: ACCEPT_CLAUDE"

# --- Malformed key spellings rejected --------------------------------------
malformed_idx=0
for bad_key_line in "XVERDICT: ACCEPT_CLAUDE" "VERDICT : ACCEPT_CLAUDE" " VERDICT: ACCEPT_CLAUDE" "VERDICTX: ACCEPT_CLAUDE"; do
  malformed_idx=$((malformed_idx + 1))
  body="$tmp_root/judgeproto-malformed-key-$malformed_idx.md"
  write_judge_body "$body" 'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' "$bad_key_line"
  state="$(run_judge_case "malformed_key_$malformed_idx" "$body" "")"
  judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
  assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
  assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
done

# --- Unknown extra line rejected (protocol otherwise complete/valid) ------
judge_unknown_line_body="$tmp_root/judgeproto-unknown-line.md"
write_judge_body "$judge_unknown_line_body" \
  'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' \
  'VERDICT: ACCEPT_CLAUDE' 'NOTE: extra explanation'
state="$(run_judge_case unknown_line "$judge_unknown_line_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

# --- Markdown-fenced protocol rejected -------------------------------------
judge_fence_body="$tmp_root/judgeproto-fence.md"
write_judge_body "$judge_fence_body" \
  '```' 'STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' \
  'VERDICT: ACCEPT_CLAUDE' '```'
state="$(run_judge_case markdown_fence "$judge_fence_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

# --- Duplicate STATUS line rejected ----------------------------------------
judge_dup_status_body="$tmp_root/judgeproto-dup-status.md"
write_judge_body "$judge_dup_status_body" \
  'STATUS: VERIFIED' 'STATUS: BLOCKED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' \
  'VERDICT: ACCEPT_CLAUDE'
state="$(run_judge_case duplicate_status "$judge_dup_status_body" "")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"

# --- Missing required field (each of the 5 independently) rejected --------
missing_idx=0
for field in STATUS CHANGED NEXT HANDOFF VERDICT; do
  missing_idx=$((missing_idx + 1))
  declare -a full_lines=('STATUS: VERIFIED' 'CHANGED: none' 'NEXT: none' 'HANDOFF: done' 'VERDICT: ACCEPT_CLAUDE')
  declare -a filtered=()
  for l in "${full_lines[@]}"; do
    [[ "$l" == "$field:"* ]] && continue
    filtered+=("$l")
  done
  body="$tmp_root/judgeproto-missing-$missing_idx.md"
  write_judge_body "$body" "${filtered[@]}"
  state="$(run_judge_case "missing_${field}" "$body" "")"
  judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
  assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
  assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
done

# --- Each allowed verdict individually accepted, correct verdict extracted
for verdict in ACCEPT_CLAUDE ACCEPT_CODEX REQUEST_REVISION BLOCKED; do
  body="$tmp_root/judgeproto-valid-$verdict.md"
  write_judge_body "$body" \
    'STATUS: VERIFIED' 'CHANGED: none' 'EVIDENCE: reviewed both proposals' \
    'NEXT: apply the accepted verdict' "HANDOFF: valid $verdict verdict" "VERDICT: $verdict"
  state="$(run_judge_case "valid_$verdict" "$body" "" 2)"
  judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
  # round-2-claude.prompt.md is built from the handoff BEFORE round 2's own
  # sections are pushed/trimmed, so it reliably captures round 1's judge
  # verdict propagation regardless of later trim_handoff eviction.
  assert_contains "$judge_run_dir/round-2-claude.prompt.md" "VERDICT: $verdict"
done

# --- Decoy token in EVIDENCE PLUS a real anchored VERDICT: only the
# anchored verdict may propagate; the decoy token must never become the
# verdict or appear as a VERDICT: line itself.
decoy_plus_real_body="$tmp_root/judgeproto-decoy-plus-real.md"
write_judge_body "$decoy_plus_real_body" \
  'STATUS: VERIFIED' 'CHANGED: none' \
  'EVIDENCE: ACCEPT_CODEX was discussed but not selected' \
  'NEXT: none' 'HANDOFF: only the anchored verdict counts' \
  'VERDICT: REQUEST_REVISION'
state="$(run_judge_case decoy_plus_real_verdict "$decoy_plus_real_body" "" 2)"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "VERDICT: REQUEST_REVISION"
assert_not_contains "$judge_run_dir/round-2-claude.prompt.md" "VERDICT: ACCEPT_CODEX"

# --- OpenCode judge invalid, agy judge valid: agy's verdict propagates,
# OpenCode's malformed output contributes nothing.
agy_valid_body="$tmp_root/judgeproto-agy-valid.md"
write_judge_body "$agy_valid_body" \
  'STATUS: VERIFIED' 'CHANGED: none' 'EVIDENCE: agy independent judge review' \
  'NEXT: none' 'HANDOFF: agy fallback judge verdict' 'VERDICT: ACCEPT_CODEX'
state="$(run_judge_case opencode_invalid_then_agy_valid "$judge_status_only_body" "$agy_valid_body" 2)"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stdout.log" "judge: OpenCode unavailable, trying agy"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "VERDICT: ACCEPT_CODEX"
assert_contains "$judge_run_dir/round-2-claude.prompt.md" "agy fallback judge verdict"
opencode_calls="$(cat "$state/opencode-count" 2>/dev/null || echo 0)"
agy_calls="$(cat "$state/agy-count" 2>/dev/null || echo 0)"
[[ "$opencode_calls" == "1" ]] || { echo "expected opencode judge invoked exactly once, got $opencode_calls" >&2; exit 1; }
[[ "$agy_calls" == "1" ]] || { echo "expected agy judge invoked exactly once, got $agy_calls" >&2; exit 1; }

# --- Both judges invalid: fails closed, JUDGE UNAVAILABLE recorded, no
# fake verdict reaches the next prompt, no consensus produced.
state="$(run_judge_case all_invalid "$judge_status_only_body" "$judge_status_only_body")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stderr.log" "provider unavailable for this session: agy"
assert_contains "$judge_run_dir/handoff.md" "JUDGE UNAVAILABLE"
assert_not_contains "$judge_run_dir/handoff.md" "JUDGE VERDICT"
assert_not_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
opencode_calls="$(cat "$state/opencode-count" 2>/dev/null || echo 0)"
agy_calls="$(cat "$state/agy-count" 2>/dev/null || echo 0)"
[[ "$opencode_calls" == "1" ]] || { echo "expected opencode judge invoked exactly once, got $opencode_calls" >&2; exit 1; }
[[ "$agy_calls" == "1" ]] || { echo "expected agy judge invoked exactly once, got $agy_calls" >&2; exit 1; }

# --- Stale judge artifact cannot be reused: a prior valid-looking output
# file must not survive to be reused by a later failed/malformed judge call.
# OpenCode is invoked first (invalid, output removed); confirm the judge
# output path does not retain any artifact once the whole call fails closed.
state="$(run_judge_case stale_artifact "$judge_status_only_body" "$judge_status_only_body")"
judge_run_dir="$(awk '/^Artifacts: / { print $2 }' "$state/stdout.log")"
[[ ! -e "$judge_run_dir/round-1-judge.out.md" ]] || {
  echo "expected no stale judge artifact to survive an all-invalid judge call" >&2
  exit 1
}

# --- Normal (non-judge) turn protocol must still reject a VERDICT line;
# VERDICT is judge-only and must never be treated as satisfying a normal
# turn's protocol (validate_turn_protocol has no VERDICT case, so a VERDICT:
# line is an unrecognized line and the whole response is rejected).
state="$(MOCK_SCENARIO=proto_verdict_line AGENT_BRIDGE_RESUME=0 run_case proto_verdict_line "$repo_dir/bin/agent-turns" "$workspace" "mock proto_verdict_line" 1)"
assert_not_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_not_contains "$state/stdout.log" "fallback: agy answered for Claude implementer"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stderr.log" "provider unavailable for this session: agy"
assert_contains "$state/stdout.log" "=== Done: CLAUDE_ERROR ==="
assert_not_contains "$state/stdout.log" "=== Done: CONSENSUS ==="

echo "mock-agent-turns: ok"
