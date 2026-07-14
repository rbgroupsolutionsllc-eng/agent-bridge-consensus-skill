#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
TEST_COUNT=0
TEST_COUNT_FILE="$tmp_root/.test_count"

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
  proto_ws_after_tab|proto_ws_between_mixed|proto_ws_indented_key|proto_verdict_line| \
  directive_model_agy|mixed_provider_directive)
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
  distinct_fallback_reviewer|independent_reviewer_unavailable|mixed_provider_directive)
    exit 1
    ;;
  directive_*)
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
  directive_*)
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
printf '%s\0' "$@" > "${MOCK_STATE}/opencode-argv-${count}.nul"
if [[ "${MOCK_SCENARIO}" == "fallback_antigravity" || "${MOCK_SCENARIO}" == "directive_model_agy" ]]; then
  exit 1
fi
case "${MOCK_SCENARIO}" in
  mixed_provider_directive)
    printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock opencode implementer via directive\nNEXT: none\nHANDOFF: opencode implemented via directive\n'
    ;;
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
printf '%s\0' "$@" > "${MOCK_STATE}/agy-argv-${count}.nul"
case "${MOCK_SCENARIO:-}" in
  mixed_provider_directive)
    printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock agy independent review via directive\nNEXT: none\nHANDOFF: agy reviewed independently via directive\n'
    ;;
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
  directive_model_agy)
    printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock agy with directive model\nNEXT: codex verifies\nHANDOFF: fallback response ready\n'
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
  # File-based counter: persists across subshells
  local n=0; [[ -f "$TEST_COUNT_FILE" ]] && n="$(cat "$TEST_COUNT_FILE")"
  echo $((n + 1)) > "$TEST_COUNT_FILE"
  MOCK_STATE="$state" PATH="$mockbin:$PATH" AGENT_BRIDGE_HOME="$bridge_home/$name" "$@" > "$state/stdout.log" 2> "$state/stderr.log"
  echo "$state"
}

run_case_fail() {
  local name="$1"
  shift
  local state="$tmp_root/state-$name"
  mkdir -p "$state"
  # File-based counter: persists across subshells
  local n=0; [[ -f "$TEST_COUNT_FILE" ]] && n="$(cat "$TEST_COUNT_FILE")"
  echo $((n + 1)) > "$TEST_COUNT_FILE"
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

# NUL-delimited argv proof helpers (P2-A). These read a mock provider's
# captured argv (written by the mock as `printf '%s\0' "$@"`) with
# mapfile -d '' so argument boundaries are exact array elements, never
# substrings of a joined "$*" string. This proves e.g. that a model value
# containing spaces/colons/semicolons was delivered as ONE argv element
# immediately following a literal "--model" element.
assert_argv_model_exact() {
  local file="$1" expected="$2" argv i found=0
  [[ -f "$file" ]] || { echo "expected argv file not found: $file" >&2; exit 1; }
  mapfile -d '' -t argv < "$file"
  for ((i = 0; i < ${#argv[@]}; i++)); do
    if [[ "${argv[$i]}" == "--model" && "${i}" -lt "$(( ${#argv[@]} - 1 ))" && "${argv[$((i + 1))]}" == "$expected" ]]; then
      found=1
      break
    fi
  done
  [[ "$found" == "1" ]] || {
    echo "expected --model element exactly followed by '$expected' in $file, got argv:" >&2
    printf '  [%s]\n' "${argv[@]}" >&2
    exit 1
  }
}

assert_argv_model_absent() {
  local file="$1" unexpected="$2" argv i
  [[ -f "$file" ]] || { echo "expected argv file not found: $file" >&2; exit 1; }
  mapfile -d '' -t argv < "$file"
  for ((i = 0; i < ${#argv[@]}; i++)); do
    if [[ "${argv[$i]}" == "--model" && "${i}" -lt "$(( ${#argv[@]} - 1 ))" && "${argv[$((i + 1))]}" == "$unexpected" ]]; then
      echo "unexpected --model element exactly followed by '$unexpected' in $file" >&2
      printf '  [%s]\n' "${argv[@]}" >&2
      exit 1
    fi
  done
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

# ===========================================================================
# Directive parsing: only [opencode:<value>] and [agy:<value>] are stripped
# from the goal. Unrelated metadata (e.g. [owner:backend]) must be preserved.
# ===========================================================================

run_directive_case() {
  local name="$1" goal="$2" expected_cleaned="$3"
  local state
  state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
    run_case "$name" "$repo_dir/bin/agent-turns" "$workspace" "$goal" 1)"
  # Find the prompt artifact containing the GOAL line
  local run_dir
  run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
  local prompt_file="$run_dir/round-1-claude.prompt.md"
  assert_contains "$prompt_file" "GOAL: $expected_cleaned"
  assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
  assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
  echo "$state"
}

# --- Unsupported tags must be preserved ---
run_directive_case "dir_owner" "Deploy API [owner:backend]" "Deploy API [owner:backend]"
run_directive_case "dir_ticket" "[ticket:ABC-123] Deploy service" "[ticket:ABC-123] Deploy service"
run_directive_case "dir_status" "Review change [status:ready]" "Review change [status:ready]"
run_directive_case "dir_foo" "[foo:bar]" "[foo:bar]"
run_directive_case "dir_owner_empty" "[owner:]" "[owner:]"
run_directive_case "dir_uppercase_opencode" "[OPENCODE:model-x]" "[OPENCODE:model-x]"
run_directive_case "dir_capital_agy" "[Agy:model-x]" "[Agy:model-x]"
run_directive_case "dir_malformed_opencode" "[opencode:model" "[opencode:model"
run_directive_case "dir_malformed_agy" "[agy:model" "[agy:model"
run_directive_case "dir_trailing_opencode" "text opencode:model]" "text opencode:model]"
run_directive_case "dir_trailing_agy" "text agy:model]" "text agy:model]"
run_directive_case "dir_plain" "[plain-brackets]" "[plain-brackets]"
run_directive_case "dir_empty" "[]" "[]"
run_directive_case "dir_unicode" "Revisar módulo [owner:operación] — 日本語 [nota:prueba]" "Revisar módulo [owner:operación] — 日本語 [nota:prueba]"
run_directive_case "dir_no_directive" "Run with no directive" "Run with no directive"

# --- Multiple unsupported tags in one goal ---
run_directive_case "dir_multi_unsupported" "[owner:backend] Deploy [status:ready] service [ticket:ABC-123]" "[owner:backend] Deploy [status:ready] service [ticket:ABC-123]"

# --- Valid opencode directive: removed from goal, model delivered ---
state="$(run_directive_case "dir_opencode_valid" "Deploy [opencode:openai/gpt-5] service" "Deploy  service")"
assert_contains "$state/opencode-args.log" "--model openai/gpt-5"

# --- Valid agy directive: removed from goal, model delivered ---
# Need both providers to fail to reach agy; directive_model_agy makes
# both Claude and OpenCode fail so agy is used as fallback.
# agy implements but can't also be reviewer (independence), so we just
# verify the GOAL line and model delivery — no consensus expected.
state="$(MOCK_SCENARIO=directive_model_agy AGENT_BRIDGE_RESUME=0 \
  run_case "dir_agy_valid" "$repo_dir/bin/agent-turns" "$workspace" \
  "Review [agy:Gemini 3.5 Flash (Medium)] change" 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_contains "$run_dir/round-1-claude.prompt.md" "GOAL: Review  change"
assert_contains "$state/stderr.log" "provider unavailable for this session: opencode"
assert_contains "$state/stdout.log" "fallback: agy answered for Claude implementer"
assert_contains "$state/agy-args.log" "--model Gemini 3.5 Flash (Medium)"

# --- Both providers plus metadata ---
run_directive_case "dir_both_plus_meta" \
  "[owner:backend] Deploy [opencode:provider/model] then review [agy:Gemini 3.5 Flash (Medium)] [ticket:ABC-123]" \
  "[owner:backend] Deploy  then review  [ticket:ABC-123]"

# --- Valid directive at beginning ---
run_directive_case "dir_position_begin" "[opencode:my-model] Deploy service" "Deploy service"

# --- Valid directive in middle ---
run_directive_case "dir_position_mid" "Deploy [opencode:my-model] service" "Deploy  service"

# --- Valid directive at end ---
run_directive_case "dir_position_end" "Deploy service [opencode:my-model]" "Deploy service"

# --- Adjacent to punctuation ---
run_directive_case "dir_adjunct_punct" "Deploy,[opencode:my-model] service." "Deploy, service."

# --- Adjacent to unsupported metadata ---
run_directive_case "dir_adjunct_meta" "[owner:backend][opencode:my-model] Deploy" "[owner:backend] Deploy"

# --- Duplicate opencode: first-match selects, both removed ---
run_directive_case "dir_dup_opencode" \
  "Run [opencode:first/model] then [opencode:second/model]" \
  "Run  then"

# --- Duplicate agy: first-match selects, both removed ---
run_directive_case "dir_dup_agy" \
  "Run [agy:first/model] then [agy:second/model]" \
  "Run  then"

# --- Colon value ---
run_directive_case "dir_colon_value" "[opencode:provider/model:variant]" ""

# --- Empty supported directives preserved ---
run_directive_case "dir_empty_opencode" "[opencode:] text" "[opencode:] text"
run_directive_case "dir_empty_agy" "[agy:] text" "[agy:] text"

# --- Shell metacharacters: no command injection ---
state="$(run_directive_case "dir_shell_opencode" "[opencode:model;printf PWNED]" "")"
[[ ! -e "$state/PWNED" ]] || { echo "FAIL: command injection via opencode directive" >&2; exit 1; }
state="$(run_directive_case "dir_shell_agy" "[agy:model\$(printf PWNED)]" "")"
[[ ! -e "$state/PWNED" ]] || { echo "FAIL: command injection via agy directive" >&2; exit 1; }

# --- Argv boundary: model with spaces passed as single argument ---
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  run_case "dir_argv_spaces" "$repo_dir/bin/agent-turns" "$workspace" \
  "Deploy [opencode:Gemini 3.5 Flash (Medium)] service" 1)"
args_line="$(cat "$state/opencode-args.log")"
# Verify --model is followed by the full value as one token (no splitting)
[[ "$args_line" == *"--model Gemini 3.5 Flash (Medium)"* ]] || \
  { echo "FAIL: model with spaces not passed as single argv: $args_line" >&2; exit 1; }

# --- Argv boundary: model with colons passed as single argument ---
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  run_case "dir_argv_colon" "$repo_dir/bin/agent-turns" "$workspace" \
  "Deploy [opencode:provider/model:variant] service" 1)"
args_line="$(cat "$state/opencode-args.log")"
[[ "$args_line" == *"--model provider/model:variant"* ]] || \
  { echo "FAIL: model with colons not passed as single argv: $args_line" >&2; exit 1; }

# --- Model delivery: opencode directive overrides env default ---
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  run_case "dir_model_opencode" "$repo_dir/bin/agent-turns" "$workspace" \
  "Deploy [opencode:custom/provider:v2] service" 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_contains "$run_dir/round-1-claude.prompt.md" "GOAL: Deploy  service"
assert_contains "$state/opencode-args.log" "--model custom/provider:v2"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="

# --- Model delivery: agy directive overrides env default ---
state="$(MOCK_SCENARIO=directive_model_agy AGENT_BRIDGE_RESUME=0 \
  run_case "dir_model_agy" "$repo_dir/bin/agent-turns" "$workspace" \
  "Review [agy:Qwen3 Coder free] change" 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_contains "$run_dir/round-1-claude.prompt.md" "GOAL: Review  change"
assert_contains "$state/agy-args.log" "--model Qwen3 Coder free"

# ===========================================================================
# Corrective fix regression coverage (P1-A/P1-B): the global CR/LF deletion
# that used to run before directive extraction is gone. Directives are now
# parsed per logical line (LF is the line separator, never directive
# content); CR inside a would-be directive invalidates it. Legitimate
# multiline goals must retain their exact newline structure, and invalid
# CR/LF-containing bracket text must never be normalized into a valid
# directive or overridden a configured model.
#
# assert_goal_block_equals extracts the exact GOAL block (from the "GOAL: "
# line up to, but excluding, the "WORKSPACE:" line) and compares it
# byte-for-byte (including embedded newlines) against the expected text —
# this is what actually proves newline structure survives, not a substring
# match against a single truncated line.
# ===========================================================================

assert_goal_block_equals() {
  local file="$1" expected="$2" actual
  actual="$(awk '/^GOAL:/{p=1} /^WORKSPACE:/{p=0} p' "$file" | sed '1s/^GOAL: //')"
  if [[ "$actual" != "$expected" ]]; then
    echo "GOAL block mismatch in $file" >&2
    echo "--- expected (cat -A) ---" >&2
    printf '%s' "$expected" | cat -A >&2
    echo "--- actual (cat -A) ---" >&2
    printf '%s' "$actual" | cat -A >&2
    exit 1
  fi
}

# --- RED regression: an ordinary multiline goal with NO directive at all
# must retain its real newline exactly (this exact input was PROVEN, against
# unmodified 9a130fd, to collapse to "Deploy serviceReview change" via the
# blanket `tr -d '\r\n'` normalization — a correctness regression on ordinary
# user input, not directive-related at all).
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  run_case "dir_plain_multiline_preserved" "$repo_dir/bin/agent-turns" "$workspace" \
  $'Deploy service\nReview change' 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" $'Deploy service\nReview change'

# --- RED regression: an LF embedded inside what looks like an opencode
# directive makes it invalid (directives cannot span lines). Against
# unmodified 9a130fd this was PROVEN to become a valid directive selecting
# model "model-x" via the same blanket CR/LF deletion. The fix must leave
# the two original lines completely unchanged and the sentinel default model
# selected (no override).
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  AGENT_BRIDGE_OPENCODE_MODEL=default-opencode-model \
  run_case "dir_newline_opencode" "$repo_dir/bin/agent-turns" "$workspace" \
  $'Deploy [opencode:model\n-x] service' 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" $'Deploy [opencode:model\n-x] service'
assert_argv_model_exact "$state/opencode-argv-1.nul" "default-opencode-model"
assert_argv_model_absent "$state/opencode-argv-1.nul" "model-x"

# --- RED regression: same defect for agy (LF-split directive). Against
# unmodified 9a130fd this was PROVEN to become a valid directive selecting
# model "model-x".
state="$(MOCK_SCENARIO=directive_model_agy AGENT_BRIDGE_RESUME=0 \
  AGENT_BRIDGE_ANTIGRAVITY_MODEL=default-agy-model \
  run_case "dir_newline_agy" "$repo_dir/bin/agent-turns" "$workspace" \
  $'Deploy [agy:model\n-x] service' 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" $'Deploy [agy:model\n-x] service'
assert_argv_model_exact "$state/agy-argv-1.nul" "default-agy-model"
assert_argv_model_absent "$state/agy-argv-1.nul" "model-x"

# --- RED regression: a CR embedded inside an opencode directive value makes
# it invalid. Against unmodified 9a130fd this was PROVEN to become a valid
# directive selecting model "modelX" (CR silently deleted, halves joined).
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  AGENT_BRIDGE_OPENCODE_MODEL=default-opencode-model \
  run_case "dir_cr_opencode" "$repo_dir/bin/agent-turns" "$workspace" \
  $'Deploy [opencode:model\rX] service' 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" $'Deploy [opencode:model\rX] service'
assert_argv_model_exact "$state/opencode-argv-1.nul" "default-opencode-model"
assert_argv_model_absent "$state/opencode-argv-1.nul" "modelX"

# --- RED regression: same defect for agy (CR-embedded directive). Against
# unmodified 9a130fd this was PROVEN to become a valid directive selecting
# model "modelX".
state="$(MOCK_SCENARIO=directive_model_agy AGENT_BRIDGE_RESUME=0 \
  AGENT_BRIDGE_ANTIGRAVITY_MODEL=default-agy-model \
  run_case "dir_cr_agy" "$repo_dir/bin/agent-turns" "$workspace" \
  $'Deploy [agy:model\rX] service' 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" $'Deploy [agy:model\rX] service'
assert_argv_model_exact "$state/agy-argv-1.nul" "default-agy-model"
assert_argv_model_absent "$state/agy-argv-1.nul" "modelX"

# --- Invalid multiline directive (LF splits the bracket expression across
# two lines) must be preserved verbatim, with no substring removed and no
# lines concatenated — proves the fix handles the case even when the split
# directive sits between two otherwise-ordinary words.
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  AGENT_BRIDGE_OPENCODE_MODEL=default-opencode-model \
  run_case "dir_invalid_multiline_verbatim" "$repo_dir/bin/agent-turns" "$workspace" \
  $'Deploy [opencode:model\ncontinued] service' 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" $'Deploy [opencode:model\ncontinued] service'
assert_argv_model_exact "$state/opencode-argv-1.nul" "default-opencode-model"

# --- Multiline goal with VALID directives on their own separate lines ---
# A directive occupying an entire line is a valid single-line directive (LF
# is the line separator, never inside the value). Multiline structure around
# it is preserved exactly; each directive-only line becomes an empty line
# (simple substring deletion of just the bracket expression on that line).
state="$(MOCK_SCENARIO=directive_model_agy AGENT_BRIDGE_RESUME=0 \
  run_case "dir_multiline_opencode" "$repo_dir/bin/agent-turns" "$workspace" \
  $'Deploy service\n[opencode:my-model]\n[agy:my-model]\nReview change' 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" $'Deploy service\n\n\nReview change'
assert_contains "$state/agy-args.log" "--model my-model"

# ===========================================================================
# STRICT DIRECTIVE GRAMMAR: extraction and stripping must recognize exactly
# the same strings — no drift between "what selects a model" and "what gets
# removed from the goal". Sentinel default models are configured explicitly
# so an override is unambiguous and distinct from either provider's natural
# CLI default.
# ===========================================================================

run_sentinel_case() {
  # run_sentinel_case <name> <provider: opencode|agy> <goal> <expected-goal>
  local name="$1" provider="$2" goal="$3" expected="$4"
  local mock_scn sentinel state run_dir argv_file
  if [[ "$provider" == "opencode" ]]; then
    mock_scn="fallback_opencode"; sentinel="default-opencode-model"
  else
    mock_scn="directive_model_agy"; sentinel="default-agy-model"
  fi
  state="$(MOCK_SCENARIO="$mock_scn" AGENT_BRIDGE_RESUME=0 \
    AGENT_BRIDGE_OPENCODE_MODEL=default-opencode-model \
    AGENT_BRIDGE_ANTIGRAVITY_MODEL=default-agy-model \
    run_case "$name" "$repo_dir/bin/agent-turns" "$workspace" "$goal" 1)"
  run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
  assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" "$expected"
  if [[ "$provider" == "opencode" ]]; then
    argv_file="$state/opencode-argv-1.nul"
  else
    argv_file="$state/agy-argv-1.nul"
  fi
  assert_argv_model_exact "$argv_file" "$sentinel"
}

# --- Empty value: no override, directive text preserved verbatim ---
run_sentinel_case "dir_sentinel_empty_opencode" opencode "[opencode:] task" "[opencode:] task"
run_sentinel_case "dir_sentinel_empty_agy" agy "[agy:] task" "[agy:] task"

# --- Uppercase provider name: no override, preserved verbatim ---
run_sentinel_case "dir_sentinel_upper_opencode" opencode "[OPENCODE:model] task" "[OPENCODE:model] task"
run_sentinel_case "dir_sentinel_upper_agy" agy "[Agy:model] task" "[Agy:model] task"

# --- Missing closing bracket: no override, preserved verbatim ---
run_sentinel_case "dir_sentinel_unterminated_opencode" opencode "[opencode:model task" "[opencode:model task"
run_sentinel_case "dir_sentinel_unterminated_agy" agy "[agy:model task" "[agy:model task"

# --- LF inside value: no override, both original lines preserved verbatim ---
run_sentinel_case "dir_sentinel_lf_opencode" opencode $'[opencode:model\ncontinued] task' $'[opencode:model\ncontinued] task'
run_sentinel_case "dir_sentinel_lf_agy" agy $'[agy:model\ncontinued] task' $'[agy:model\ncontinued] task'

# --- CR inside value: no override, preserved verbatim (single line) ---
run_sentinel_case "dir_sentinel_cr_opencode" opencode $'[opencode:model\rcontinued] task' $'[opencode:model\rcontinued] task'
run_sentinel_case "dir_sentinel_cr_agy" agy $'[agy:model\rcontinued] task' $'[agy:model\rcontinued] task'

# --- CRLF inside value: no override, preserved verbatim (two lines, second
# line starts with a lone CR as its first byte) ---
run_sentinel_case "dir_sentinel_crlf_opencode" opencode $'[opencode:model\r\ncontinued] task' $'[opencode:model\r\ncontinued] task'
run_sentinel_case "dir_sentinel_crlf_agy" agy $'[agy:model\r\ncontinued] task' $'[agy:model\r\ncontinued] task'

# ===========================================================================
# ARGV BOUNDARY PROOF (P2-A fix): replace $*-substring matching with
# NUL-delimited argv capture, verified by exact array index/element — never
# by substring containment of a joined string.
# ===========================================================================

# --- Duplicate opencode: first-match selects, proven by exact argv element
# immediately after a literal "--model" element; the second value is never
# selected as the model argument anywhere in the captured argv. ---
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  run_case "dir_dup_opencode_argv" "$repo_dir/bin/agent-turns" "$workspace" \
  "Run [opencode:first/model] then [opencode:second/model]" 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_argv_model_exact "$state/opencode-argv-1.nul" "first/model"
assert_argv_model_absent "$state/opencode-argv-1.nul" "second/model"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" "Run  then"

# --- Duplicate agy: first-match selects, proven by exact argv element. ---
state="$(MOCK_SCENARIO=directive_model_agy AGENT_BRIDGE_RESUME=0 \
  run_case "dir_dup_agy_argv" "$repo_dir/bin/agent-turns" "$workspace" \
  "Run [agy:first/model] then [agy:second/model]" 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_argv_model_exact "$state/agy-argv-1.nul" "first/model"
assert_argv_model_absent "$state/agy-argv-1.nul" "second/model"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" "Run  then"

# --- Model with spaces delivered as exactly one argv element (not split). ---
state="$(MOCK_SCENARIO=fallback_opencode AGENT_BRIDGE_RESUME=0 \
  run_case "dir_argv_spaces_exact" "$repo_dir/bin/agent-turns" "$workspace" \
  "Deploy [opencode:Gemini 3.5 Flash (Medium)] service" 1)"
assert_argv_model_exact "$state/opencode-argv-1.nul" "Gemini 3.5 Flash (Medium)"

# --- Mixed providers: both models extracted from the same goal string, each
# proven via its own provider's exact NUL-delimited argv. ---
state="$(MOCK_SCENARIO=directive_model_agy AGENT_BRIDGE_RESUME=0 \
  run_case "dir_mixed_providers" "$repo_dir/bin/agent-turns" "$workspace" \
  "Deploy [opencode:my-model] service [agy:Qwen3 Coder free] now" 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" "Deploy  service  now"
assert_argv_model_exact "$state/agy-argv-1.nul" "Qwen3 Coder free"

# ===========================================================================
# SHELL-SAFETY: directive values are inert data end-to-end. No command
# substitution, backtick execution, glob expansion, or variable expansion
# ever occurs, regardless of value content. Proven via NUL-delimited argv
# (exact single element, byte-for-byte) plus absence of any marker file or
# unexpected output that execution/expansion would have produced.
# ===========================================================================

run_shell_safety_case() {
  # run_shell_safety_case <name> <provider: opencode|agy> <literal-value>
  local name="$1" provider="$2" value="$3"
  local mock_scn state run_dir argv_file
  if [[ "$provider" == "opencode" ]]; then
    mock_scn="fallback_opencode"
  else
    mock_scn="directive_model_agy"
  fi
  state="$(MOCK_SCENARIO="$mock_scn" AGENT_BRIDGE_RESUME=0 \
    run_case "$name" "$repo_dir/bin/agent-turns" "$workspace" \
    "Deploy [${provider}:${value}] service" 1)"
  run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
  assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" "Deploy  service"
  if [[ "$provider" == "opencode" ]]; then
    argv_file="$state/opencode-argv-1.nul"
  else
    argv_file="$state/agy-argv-1.nul"
  fi
  assert_argv_model_exact "$argv_file" "$value"
  [[ ! -e "$state/PWNED" ]] || { echo "FAIL: command injection via $provider directive ($name)" >&2; exit 1; }
  [[ ! -e "$tmp_root/PWNED" ]] || { echo "FAIL: command injection via $provider directive ($name, tmp_root)" >&2; exit 1; }
  [[ -z "$(find "$tmp_root" -maxdepth 1 -newer "$state/stdout.log" -name 'PWNED*' 2>/dev/null)" ]] || \
    { echo "FAIL: unexpected PWNED-named artifact via $provider directive ($name)" >&2; exit 1; }
}

# --- semicolon: no command chaining ---
run_shell_safety_case "dir_safety_semicolon_opencode" opencode 'model;printf PWNED'
run_shell_safety_case "dir_safety_semicolon_agy" agy 'model;printf PWNED'

# --- $(...) command substitution: no execution ---
run_shell_safety_case "dir_safety_dollarparen_opencode" opencode 'model$(printf PWNED)'
run_shell_safety_case "dir_safety_dollarparen_agy" agy 'model$(printf PWNED)'

# --- backticks: no execution ---
run_shell_safety_case "dir_safety_backtick_opencode" opencode 'model`printf PWNED`'
run_shell_safety_case "dir_safety_backtick_agy" agy 'model`printf PWNED`'

# --- glob characters (* and ?): no expansion against real files ---
run_shell_safety_case "dir_safety_glob_star_opencode" opencode 'model-*-variant'
run_shell_safety_case "dir_safety_glob_star_agy" agy 'model-*-variant'
run_shell_safety_case "dir_safety_glob_question_opencode" opencode 'model-?-variant'
run_shell_safety_case "dir_safety_glob_question_agy" agy 'model-?-variant'

# --- opening bracket in value: no injection, delivered literally ---
run_shell_safety_case "dir_safety_open_bracket_opencode" opencode 'model[tag'
run_shell_safety_case "dir_safety_open_bracket_agy" agy 'model[tag'

# --- colon in value: no injection, delivered literally ---
run_shell_safety_case "dir_safety_colon_opencode" opencode 'provider/model:variant'
run_shell_safety_case "dir_safety_colon_agy" agy 'provider/model:variant'

# --- variable expansion attempt: no expansion (literal $HOME-looking text) ---
run_shell_safety_case "dir_safety_var_expand_opencode" opencode 'model-$HOME-variant'
run_shell_safety_case "dir_safety_var_expand_agy" agy 'model-$HOME-variant'

# ===========================================================================
# MIXED-PROVIDER EXECUTION (P2-B fix): a single mocked round where Claude and
# Codex both fail, OpenCode serves as the fallback implementer and agy serves
# as the fallback reviewer, and BOTH providers are actually invoked (proven
# by per-provider invocation counts and per-provider exact argv), in the same
# run, with the existing P0 distinct-identity enforcement still active. A
# scenario that only invokes agy (as previously existed) would NOT satisfy
# this: both providers' models must be proven delivered in the same round.
# ===========================================================================

state="$(MOCK_SCENARIO=mixed_provider_directive AGENT_BRIDGE_RESUME=0 \
  run_case "dir_mixed_provider_execution" "$repo_dir/bin/agent-turns" "$workspace" \
  "[owner:backend] Deploy [opencode:o1] then review [agy:a1] [ticket:ABC-123]" 1)"
run_dir="$(awk '/^Run: / { print $2 }' "$state/stdout.log")"
assert_contains "$state/stdout.log" "fallback: opencode answered for Claude implementer"
assert_contains "$state/stdout.log" "fallback: agy answered for Codex reviewer"
assert_contains "$state/stdout.log" "=== Done: CONSENSUS ==="
assert_goal_block_equals "$run_dir/round-1-claude.prompt.md" \
  "[owner:backend] Deploy  then review  [ticket:ABC-123]"
assert_argv_model_exact "$state/opencode-argv-1.nul" "o1"
assert_argv_model_exact "$state/agy-argv-1.nul" "a1"
opencode_calls="$(cat "$state/opencode-count")"
agy_calls="$(cat "$state/agy-count")"
[[ "$opencode_calls" == "1" ]] || { echo "expected opencode invoked exactly once, got $opencode_calls" >&2; exit 1; }
[[ "$agy_calls" == "1" ]] || { echo "expected agy invoked exactly once, got $agy_calls" >&2; exit 1; }
# P0 still enforced: the reviewer identity (agy) must differ from the
# implementer identity (opencode) — the run must never accept a same-provider
# self-review even in this mixed-directive scenario.
assert_not_contains "$state/stdout.log" "independent reviewer unavailable"

# ===========================================================================
# INSTALLER REGRESSION: first-line bridge section replacement idempotently
# ===========================================================================

run_installer_case() {
  local name="$1" input="$2"
  local case_home="$tmp_root/installer-$name"
  mkdir -p "$case_home/.config/opencode"
  printf '%s' "$input" > "$case_home/.config/opencode/AGENTS.md"
  local state
  # Increment test counter (file-based, persists across subshells)
  local n=0; [[ -f "$TEST_COUNT_FILE" ]] && n="$(cat "$TEST_COUNT_FILE")"
  echo $((n + 1)) > "$TEST_COUNT_FILE"
  state="$(HOME="$case_home" MOCK_STATE="$case_home/state" PATH="$mockbin:$PATH" \
    AGENT_BRIDGE_HOME="$bridge_home/$name" bash -c 'mkdir -p "$HOME/.config/opencode" && '"$repo_dir/bin/install-local" 2>&1)"
  echo "$case_home"
}

# CASE 1 — FILE DOES NOT EXIST
# (rm -f to ensure no file, then run)
case_home="$(run_installer_case file_missing "")"
assert_contains "$case_home/.config/opencode/AGENTS.md" "You are part of a 4-agent team: Claude (implementer), Codex (reviewer), OpenCode (judge + 1st fallback), agy (2nd fallback)."
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 2 — EMPTY FILE
case_home="$(run_installer_case empty_file "")"
assert_contains "$case_home/.config/opencode/AGENTS.md" "Token rule: protocol block only. No preamble. Do not mark COMPLETE for your own unverified work."
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 3 — MANAGED SECTION AT FIRST LINE THROUGH EOF
case_home="$(run_installer_case first_line_eof $'## Agent Bridge Consensus\n\nOLD FIRST-LINE CONTENT')"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD FIRST-LINE CONTENT"
assert_contains "$case_home/.config/opencode/AGENTS.md" "You are part of a 4-agent team: Claude (implementer), Codex (reviewer), OpenCode (judge + 1st fallback), agy (2nd fallback)."
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 4 — FIRST LINE FOLLOWED BY ANOTHER H2
case_home="$(run_installer_case first_line_following_h2 $'## Agent Bridge Consensus\n\nOLD CONTENT\n\n## Existing Project Rules\n\nKEEP THIS RULE')"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD CONTENT"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## Existing Project Rules"
assert_contains "$case_home/.config/opencode/AGENTS.md" "KEEP THIS RULE"
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 5 — MANAGED SECTION IN MIDDLE
case_home="$(run_installer_case middle_section $'PREFACE\n\n## Agent Bridge Consensus\n\nOLD MIDDLE CONTENT\n\n## Existing Rules\n\nKEEP THIS')"
assert_contains "$case_home/.config/opencode/AGENTS.md" "PREFACE"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## Existing Rules"
assert_contains "$case_home/.config/opencode/AGENTS.md" "KEEP THIS"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD MIDDLE CONTENT"
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 6 — MANAGED SECTION AT END
case_home="$(run_installer_case end_section $'# Preface\n\nSome intro content.\n\n## Agent Bridge Consensus\n\nOLD AT END')"
assert_contains "$case_home/.config/opencode/AGENTS.md" "Preface"
assert_contains "$case_home/.config/opencode/AGENTS.md" "Some intro content"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD AT END"
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 7 — TWO PREEXISTING MANAGED SECTIONS
case_home="$(run_installer_case two_sections $'intro\n\n## Agent Bridge Consensus\n\nOLD ONE\n\n## Other\n\nKEEP\n\n## Agent Bridge Consensus\n\nOLD TWO')"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD ONE"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD TWO"
assert_contains "$case_home/.config/opencode/AGENTS.md" "intro"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## Other"
assert_contains "$case_home/.config/opencode/AGENTS.md" "KEEP"
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 8 — THREE PREEXISTING MANAGED SECTIONS
case_home="$(run_installer_case three_sections $'intro\n\n## Agent Bridge Consensus\n\nOLD ONE\n\n## Other\n\nKEEP\n\n## Agent Bridge Consensus\n\nOLD TWO\n\n## More\n\nKEEP2\n\n## Agent Bridge Consensus\n\nOLD THREE')"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD ONE"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD TWO"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD THREE"
assert_contains "$case_home/.config/opencode/AGENTS.md" "intro"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## Other"
assert_contains "$case_home/.config/opencode/AGENTS.md" "KEEP"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## More"
assert_contains "$case_home/.config/opencode/AGENTS.md" "KEEP2"
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 9 — SIMILAR HEADINGS MUST NOT MATCH
case_home="$(run_installer_case similar_headings $'### Agent Bridge Consensus\n\n## Agent Bridge Consensus Extra\n\n## agent bridge consensus\n\nText mentioning Agent Bridge Consensus in prose.\n\n## Agent Bridge Consensus\n\nOLD CONTENT')"
# All similar headings preserved
assert_contains "$case_home/.config/opencode/AGENTS.md" "### Agent Bridge Consensus"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## Agent Bridge Consensus Extra"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## agent bridge consensus"
# Prose text preserved
assert_contains "$case_home/.config/opencode/AGENTS.md" "Text mentioning Agent Bridge Consensus in prose."
# Exactly one exact managed heading
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 exact managed heading, got $count" >&2; exit 1; }

# CASE 10 — INPUT WITHOUT FINAL NEWLINE
case_home="$(run_installer_case no_final_newline $'# Test\n\nContent without newline')"
# Should end with exactly one LF
last_byte=$(tail -c1 "$case_home/.config/opencode/AGENTS.md" | od -An -tx1 | tr -d ' \n')
[[ "$last_byte" == "0a" ]] || { echo "expected final LF, got $last_byte" >&2; exit 1; }
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 11 — BLANK-LINE STABILITY (three runs)
case_home="$(run_installer_case blank_line_stability_1 $'\n\n## Agent Bridge Consensus\n\n\nOLD\n\n\n')"
out1="$(cat "$case_home/.config/opencode/AGENTS.md")"
case_home="$(run_installer_case blank_line_stability_2 "$out1")"
out2="$(cat "$case_home/.config/opencode/AGENTS.md")"
case_home="$(run_installer_case blank_line_stability_3 "$out2")"
out3="$(cat "$case_home/.config/opencode/AGENTS.md")"
[[ "$out1" == "$out2" ]] || { echo "blank-line growth detected: run1 != run2" >&2; exit 1; }
[[ "$out2" == "$out3" ]] || { echo "blank-line growth detected: run2 != run3" >&2; exit 1; }
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading after 3 runs, got $count" >&2; exit 1; }

# CASE 12 — UNICODE CONTENT
case_home="$(run_installer_case unicode $'# Привет\n\nПривет мир 🌍\n\n## Agent Bridge Consensus\n\nOLD')"
assert_contains "$case_home/.config/opencode/AGENTS.md" "Привет"
assert_contains "$case_home/.config/opencode/AGENTS.md" "🌍"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD"
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 13 — THREE-RUN IDEMPOTENCE FROM CLEAN FILE
case_home="$(run_installer_case idempotence_1 $'## Agent Bridge Consensus\n\nOLD')"
h1=$(sha256sum "$case_home/.config/opencode/AGENTS.md" | cut -d' ' -f1)
case_home="$(run_installer_case idempotence_2 "$(cat "$case_home/.config/opencode/AGENTS.md")")"
h2=$(sha256sum "$case_home/.config/opencode/AGENTS.md" | cut -d' ' -f1)
case_home="$(run_installer_case idempotence_3 "$(cat "$case_home/.config/opencode/AGENTS.md")")"
h3=$(sha256sum "$case_home/.config/opencode/AGENTS.md" | cut -d' ' -f1)
[[ "$h1" == "$h2" ]] && [[ "$h2" == "$h3" ]] || { echo "idempotence hash mismatch: $h1 $h2 $h3" >&2; exit 1; }
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

# CASE 14 — FOLLOWING SECTION WITH EMPTY BODY
case_home="$(run_installer_case following_empty $'## Agent Bridge Consensus\n\nOLD\n\n## Following')"
assert_contains "$case_home/.config/opencode/AGENTS.md" "## Following"
assert_not_contains "$case_home/.config/opencode/AGENTS.md" "OLD"
count=$(grep -c '^## Agent Bridge Consensus$' "$case_home/.config/opencode/AGENTS.md" || true)
[[ "$count" == "1" ]] || { echo "expected 1 managed heading, got $count" >&2; exit 1; }

TEST_COUNT=0
[[ -f "$TEST_COUNT_FILE" ]] && TEST_COUNT="$(cat "$TEST_COUNT_FILE")"
echo "mock-agent-turns: ok ($TEST_COUNT cases)"
