#!/usr/bin/env bash
# Gate 14B — regresión permanente de los 4 hallazgos CONFIRMED (14A).
# Solo mocks (claude/codex/opencode/agy falsos). Sin agentes reales ni claves.
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
engine="$repo_dir/bin/agent-turns"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/gate14b-work-XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
mockbin="$tmp_root/bin"
mkdir -p "$mockbin"
total=0
ok_count=0

# ── mocks ────────────────────────────────────────────────────────────────────
cat > "$mockbin/claude" <<'EOF'
#!/usr/bin/env bash
[[ -n "${MOCK_CLAUDE_FAIL:-}" ]] && exit 1
[[ "${MOCK_CLAUDE_EFFECT:-}" == "write" && -n "${MOCK_WS:-}" ]] && echo "un-declared-change" > "$MOCK_WS/sneaky.txt"
json=0; _p=""
for a in "$@"; do [[ "$_p" == "--output-format" && "$a" == "json" ]] && json=1; _p="$a"; done
if [[ "$json" == "1" ]]; then
  python3 -c 'import sys,json; print(json.dumps({"result": open(sys.argv[1]).read(), "session_id": "m", "total_cost_usd": 0.0}))' "$MOCK_CLAUDE_FILE"
else
  cat "$MOCK_CLAUDE_FILE"
fi
exit 0
EOF

cat > "$mockbin/codex" <<'EOF'
#!/usr/bin/env bash
[[ -n "${MOCK_CODEX_FAIL:-}" ]] && exit 1
out=""; _p=""
for a in "$@"; do
  [[ "$_p" == "--output-last-message" ]] && out="$a"
  _p="$a"
done
cat "${MOCK_CODEX_FILE:?}" > "$out"
exit 0
EOF

cat > "$mockbin/opencode" <<'EOF'
#!/usr/bin/env bash
[[ -n "${MOCK_OPENCODE_FILE:-}" && -f "$MOCK_OPENCODE_FILE" ]] && { cat "$MOCK_OPENCODE_FILE"; exit 0; }
exit 1
EOF

cat > "$mockbin/agy" <<'EOF'
#!/usr/bin/env bash
[[ -n "${MOCK_AGY_FILE:-}" && -f "$MOCK_AGY_FILE" ]] && { cat "$MOCK_AGY_FILE"; exit 0; }
exit 1
EOF

export PATH="$mockbin:$PATH"
chmod +x "$mockbin"/claude "$mockbin"/codex "$mockbin"/opencode "$mockbin"/agy

case_pass() { total=$((total+1)); ok_count=$((ok_count+1)); printf 'PASS %s\n' "$1" >&2; }
case_fail() {
  total=$((total+1))
  echo "FAIL $1 :: esper=$2 obt=rc=$3" >&2
  if [[ -n "${4:-}" ]]; then echo "  detalle: $4" >&2; fi
  [[ -n "${RUN_FULL:-}" ]] && { echo "  --- salida completa ---" >&2; sed 's/^/  /' "${5:-}" >&2; }
}

# run_case <nombre> <archivo-claude> <archivo-codex> <verify_cmd|-> <workspace-subdir-or-> <env-extras...>
# run_case2 wrapper que captura rc reales (la función anterior no puede exportar RC)
run_case2() {
  local name="$1" cfile="$2" xfile="$3" vcmd="$4" wsub="$5" wsmkdir="${6:-1}"; shift 5
  local home="$tmp_root/bridge-$name"
  rm -rf "$home"; mkdir -p "$home"
  if [[ "$wsmkdir" == "1" ]]; then mkdir -p "$tmp_root/workspace/$wsub"; fi
  (
    cd "/tmp"
    export MOCK_CLAUDE_FILE="$cfile" MOCK_CODEX_FILE="$xfile" AGENT_BRIDGE_HOME="$home"
    if [[ "$vcmd" != "-" ]]; then export AGENT_BRIDGE_VERIFY_CMD="$vcmd"; else unset AGENT_BRIDGE_VERIFY_CMD; fi
    [[ -n "${MOCK_WS:-}" ]] || true
    exec bash "$engine" "${1:-$tmp_root/workspace/$wsub}" "objetivo ${name}" 2
  ) > "$tmp_root/${name}.full" 2>&1
  RUN_RC=$?
}

prep_case() {
  local wsub="$1"; shift
  : > "$tmp_root/ws_state_${wsub//\//_}.log"
}

# ── caso 1: consenso legítimo sin cambios → CONSENSUS rc=0 ──────────────────
printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c1c.txt"
printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: mock rev\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c1r.txt"
run_case2 consensus_ok "$tmp_root/c1c.txt" "$tmp_root/c1r.txt" "-" clean1
if [[ $RUN_RC -eq 0 ]] && grep -q "Done: CONSENSUS" "$tmp_root/consensus_ok.full"; then case_pass consensus_ok; else case_fail consensus_ok "rc0+CONSENSUS" "$RUN_RC" "" "$tmp_root/consensus_ok.full"; fi

# ── caso 2: BLOCKED del revisor → BLOCKED rc=3 ───────────────────────────────
printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c2c.txt"
printf 'STATUS: BLOCKED\nCHANGED: none\nEVIDENCE: blocked\nNEXT: none\nHANDOFF: stop\n' > "$tmp_root/c2r.txt"
run_case2 blocked_reviewer "$tmp_root/c2c.txt" "$tmp_root/c2r.txt" "-" clean2
if [[ $RUN_RC -eq 3 ]] && grep -q "Done: BLOCKED" "$tmp_root/blocked_reviewer.full"; then case_pass blocked_reviewer; else case_fail blocked_reviewer "rc3+BLOCKED" "$RUN_RC" "" "$tmp_root/blocked_reviewer.full"; fi

# ── caso 3: claude declara CHANGED y verify falla → VERIFY_FAILING rc=2 ─────
printf 'STATUS: PROPOSED\nCHANGED: changed.txt\nEVIDENCE: mock\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c3c.txt"
printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: ok\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c3r.txt"
run_case2 verify_failing_declared "$tmp_root/c3c.txt" "$tmp_root/c3r.txt" "false" clean3
if [[ $RUN_RC -eq 2 ]] && grep -q "Done: VERIFY_FAILING" "$tmp_root/verify_failing_declared.full"; then case_pass verify_failing_declared; else case_fail verify_failing_declared "rc2+VERIFY_FAILING" "$RUN_RC" "" "$tmp_root/verify_failing_declared.full"; fi

# ── caso 4: delta real SIN verify_cmd → consenso rechazado rc=2 (P0-3 fail closed) ─
printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: mock\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c4c.txt"
printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: ok\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c4r.txt"
rm -rf "$tmp_root/workspace/tamper4"; mkdir -p "$tmp_root/workspace/tamper4"
( cd "$tmp_root/workspace/tamper4" && MOCK_WS="$tmp_root/workspace/tamper4" MOCK_CLAUDE_EFFECT=write \
  MOCK_CLAUDE_FILE="$tmp_root/c4c.txt" MOCK_CODEX_FILE="$tmp_root/c4r.txt" AGENT_BRIDGE_HOME="$tmp_root/bridge-tamper4" \
  bash "$engine" "$tmp_root/workspace/tamper4" "tamper" 2 > "$tmp_root/tamper4.full" 2>&1; echo $? > "$tmp_root/tamper4.rc" )
if [[ "$(cat "$tmp_root/tamper4.rc")" -eq 2 ]] && grep -q "Done: VERIFY_FAILING" "$tmp_root/tamper4.full" \
   && grep -q "objective verification" "$tmp_root/tamper4.full"; then case_pass tamper_no_verify_cmd; else case_fail tamper_no_verify_cmd "rc2+VERIFY_FAILING+note" "$(cat "$tmp_root/tamper4.rc")" "" "$tmp_root/tamper4.full"; fi

# ── caso 5: mentira CHANGED:none con verify=false → verify corre (delta real) y rc=2 ─
rm -rf "$tmp_root/workspace/tamper5" "$tmp_root/verify-marker.log"; mkdir -p "$tmp_root/workspace/tamper5"
( cd "$tmp_root/workspace/tamper5" && MOCK_WS="$tmp_root/workspace/tamper5" MOCK_CLAUDE_EFFECT=write \
  MOCK_CLAUDE_FILE="$tmp_root/c4c.txt" MOCK_CODEX_FILE="$tmp_root/c4r.txt" AGENT_BRIDGE_HOME="$tmp_root/bridge-tamper5" \
  AGENT_BRIDGE_VERIFY_CMD="echo VERIFY-RAN >> $tmp_root/verify-marker.log; false" \
  bash "$engine" "$tmp_root/workspace/tamper5" "tamper" 2 > "$tmp_root/tamper5.full" 2>&1; echo $? > "$tmp_root/tamper5.rc" )
if [[ "$(cat "$tmp_root/tamper5.rc")" -eq 2 ]] && grep -q "VERIFY-RAN" $tmp_root/verify-marker.log \
   && grep -q "Done: VERIFY_FAILING" "$tmp_root/tamper5.full"; then case_pass changed_none_lie_caught; else case_fail changed_none_lie_caught "rc2+verify-corrió" "$(cat "$tmp_root/tamper5.rc")" "" "$tmp_root/tamper5.full"; fi

# ── caso 6: revisor primario codex protocolo inválido → nunca CONSENSUS (rc=5 CODEX_ERROR) ─
cat > "$tmp_root/c6r.txt" <<'EOF'
Revisé el trabajo del implementador, parece correcto.

STATUS: VERIFIED
CHANGED: none
EVIDENCE: nadie me valida estructuralmente... ¿entrenamiento 14B?

NEXT: ninguna
HANDOFF: ok con narración previa y campo duplicado abajo
NEXT: línea inválida extra
EOF
run_case2 invalid_codex_protocol "$tmp_root/c1c.txt" "$tmp_root/c6r.txt" "true" clean6
if [[ $RUN_RC -eq 5 ]] && grep -q "Done: CODEX_ERROR" "$tmp_root/invalid_codex_protocol.full" \
   && ! grep -q "Done: CONSENSUS" "$tmp_root/invalid_codex_protocol.full"; then case_pass invalid_codex_protocol; else case_fail invalid_codex_protocol "rc5+CODEX_ERROR" "$RUN_RC" "" "$tmp_root/invalid_codex_protocol.full"; fi

# ── caso 7: desacuerdo persistente → MAX_ROUNDS rc=1 ────────────────────────
printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: no confío\nNEXT: revisar\nHANDOFF: discrepancia\n' > "$tmp_root/c7r.txt"
run_case2 max_rounds "$tmp_root/c1c.txt" "$tmp_root/c7r.txt" "-" clean7
if [[ $RUN_RC -eq 1 ]] && grep -q "Done: MAX_ROUNDS" "$tmp_root/max_rounds.full"; then case_pass max_rounds; else case_fail max_rounds "rc1+MAX_ROUNDS" "$RUN_RC" "" "$tmp_root/max_rounds.full"; fi

export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c1r.txt"
# ── caso 8: allowlist estricta — workspace no autorizado → exit 7, sin run ──
HOME_NS="$tmp_root/fakehome"; mkdir -p "$HOME_NS"
( cd "/tmp"
  HOME="$HOME_NS" AGENT_BRIDGE_ALLOWED_WORKSPACES="/tmp/gate14b-other-place:${tmp_root}/authorized-only" \
  AGENT_BRIDGE_HOME="$tmp_root/bridge-wsauth" \
  bash "$engine" "$tmp_root/workspace/clean1" "objetivo allowlist" 2 > "$tmp_root/ws_auth.full" 2>&1; echo $? > "$tmp_root/ws_auth.rc" )
if [[ "$(cat "$tmp_root/ws_auth.rc")" -eq 7 ]] && ! grep -q "^Run:" "$tmp_root/ws_auth.full" \
   && grep -q "Workspace not authorized" "$tmp_root/ws_auth.full"; then case_pass allowlist_reject; else case_fail allowlist_reject "rc7+rechazo" "$(cat "$tmp_root/ws_auth.rc")" "" "$tmp_root/ws_auth.full"; fi

# ── caso 8b: allowlist con ruta equivalente vía symlink → mismo canon → permitido ─
link_dir="$tmp_root/workspace/$$-link"
ln -s "$tmp_root/workspace/clean1" "$link_dir"
( cd "/tmp"
  HOME="$HOME_NS" AGENT_BRIDGE_ALLOWED_WORKSPACES="$tmp_root/workspace/clean1" \
  AGENT_BRIDGE_HOME="$tmp_root/bridge-wslink" \
  bash "$engine" "$link_dir" "objetivo symlink-equivalente" 2 > "$tmp_root/ws_link.full" 2>&1; echo $? > "$tmp_root/ws_link.rc" )
# con mocks de consenso válido (c1c/c1r), la corrida llega a CONSENSUS y rc=0
if [[ "$(cat "$tmp_root/ws_link.rc")" -eq 0 ]] && grep -q "workspace authorized" "$tmp_root/ws_link.full"; then case_pass allowlist_symlink_eq; else case_fail allowlist_symlink_eq "rc0 (canon igual)" "$(cat "$tmp_root/ws_link.rc")" "" "$tmp_root/ws_link.full"; fi

# ── caso 9: independencia preservada — claude falla → opencode implementa; codex falla → revisor NO-opencode ─
export MOCK_CLAUDE_FAIL=1
printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: fallback impl\nNEXT: none\nHANDOFF: listo\n' > "$tmp_root/c9o.txt"
export MOCK_OPENCODE_FILE="$tmp_root/c9o.txt"
export MOCK_CODEX_FAIL=1
printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: agy revisó\nNEXT: none\nHANDOFF: agy ok\n' > "$tmp_root/c9a.txt"
export MOCK_AGY_FILE="$tmp_root/c9a.txt"
run_case2 independence_fallback "$tmp_root/c1c.txt" "$tmp_root/c1r.txt" "-" clean1
if [[ $RUN_RC -eq 0 ]] && grep -q "Implementer (opencode)" "$tmp_root/independence_fallback.full" \
   && grep -q "Reviewer (agy)" "$tmp_root/independence_fallback.full" \
   && grep -q "Done: CONSENSUS" "$tmp_root/independence_fallback.full"; then
  case_pass independence_fallback
else
  case_fail independence_fallback "opencode impl + agy review + CONSENSUS rc0" "$RUN_RC" "" "$tmp_root/independence_fallback.full"
fi
unset MOCK_CLAUDE_FAIL MOCK_CODEX_FAIL MOCK_OPENCODE_FILE MOCK_AGY_FILE

if [[ $ok_count -eq $total ]]; then
  echo "redteam-gate14b: ok ($ok_count casos)"
  exit 0
fi
echo "redteam-gate14b: $ok_count/$total casos pasaron"
exit 1
