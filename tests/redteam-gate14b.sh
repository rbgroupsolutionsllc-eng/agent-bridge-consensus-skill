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
skip_count=0

case_skip() { skip_count=$((skip_count+1)); printf 'SKIP %s (requiere id -u != 0: %s)\n' "$1" "$2" >&2; }

# ── mocks ────────────────────────────────────────────────────────────────────
cat > "$mockbin/claude" <<'EOF'
#!/usr/bin/env bash
[[ -n "${MOCK_CLAUDE_FAIL:-}" ]] && exit 1
if [[ "${MOCK_CLAUDE_EFFECT:-}" == "write" && -n "${MOCK_WS:-}" ]]; then
  echo "un-declared-change" > "$MOCK_WS/sneaky.txt"
elif [[ "${MOCK_CLAUDE_EFFECT:-}" == "rewrite_same_meta" && -n "${MOCK_WS:-}" ]]; then
  # Gate 14B.1: modifica contenido conservando EXACTAMENTE tamaño y mtime
  # (16 bytes, mismo atime/mtime) para forzar el falso negativo de un
  # detector basado solo en metadatos.
  python3 - "$MOCK_WS/gen.txt" <<'PY'
import os, sys
p = sys.argv[1]
st = os.stat(p)
with open(p, "w") as f:
    f.write("GROUND-1-TRUTH-2")
os.utime(p, (st.st_atime, st.st_mtime))
assert os.stat(p).st_size == st.st_size
assert os.stat(p).st_mtime_ns == st.st_mtime_ns
PY
fi
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
# Gate 14B.4.1: con MOCK_CODEX_COUNT_FILE activado, la 1ª invocación (revisor r1)
# devuelve DISAGREE; las siguientes usan el archivo clásico (VERIFIED en r2).
if [[ -n "${MOCK_CODEX_COUNT_FILE:-}" ]]; then
  c=0; [[ -f "$MOCK_CODEX_COUNT_FILE" ]] && c="$(cat "$MOCK_CODEX_COUNT_FILE")"
  c=$((c+1)); echo "$c" > "$MOCK_CODEX_COUNT_FILE"
  if [[ "$c" -eq 1 ]]; then
    printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: rev r1\nNEXT: none\nHANDOFF: disputa r1\n' > "$out"
    exit 0
  fi
fi
cat "${MOCK_CODEX_FILE:?}" > "$out"
exit 0
EOF

cat > "$mockbin/opencode" <<'EOF'
#!/usr/bin/env bash
# Gate 14B.4.2: el ROL se registra por el contenido del prompt (ask-opencode
# pasa `$(cat "prompt")` como un solo argumento; el prompt del árbitro contiene
# "third-party judge"). El hit-file deja registro inequívoco de proveedor+rol.
isjudge=0
for a in "$@"; do
  [[ "$a" == *"third-party judge"* ]] && isjudge=1
done
if [[ "$isjudge" -eq 1 ]]; then
  [[ -n "${MOCK_OPENCODE_JUDGE_HIT:-}" ]] && printf 'judge\n' > "$MOCK_OPENCODE_JUDGE_HIT"
  [[ -n "${MOCK_JUDGE_WS_WRITE:-}" ]] && printf 'judge-touched\n' > "${MOCK_JUDGE_WS_WRITE}/SNEAKY-BY-JUDGE.txt"
  [[ -n "${MOCK_JUDGE_WS_UNREAD:-}" ]] && { printf 'locked-by-judge\n' > "${MOCK_JUDGE_WS_WRITE}/LOCKED-BY-JUDGE.txt"; chmod 000 "${MOCK_JUDGE_WS_WRITE}/LOCKED-BY-JUDGE.txt"; }
  if [[ -n "${MOCK_OPENCODE_JUDGE_FILE:-}" && -f "$MOCK_OPENCODE_JUDGE_FILE" ]]; then
    cat "$MOCK_OPENCODE_JUDGE_FILE"; exit 0
  fi
  printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: judge r1\nNEXT: none\nHANDOFF: veredicto viz\nVERDICT: REQUEST_REVISION\n'
  exit 0
fi
# Gate 14B.4.1: con MOCK_OPENCODE_COUNT_FILE y sin rol de juez, la 1ª
# invocación es el intento de fallback del implementador (r1) que fuerza la
# disputa; el resto usa el archivo clásico. Sin la variable, el mock clásico
# por archivo queda intacto para los casos 1-14.
if [[ -n "${MOCK_OPENCODE_COUNT_FILE:-}" ]]; then
  c=0; [[ -f "$MOCK_OPENCODE_COUNT_FILE" ]] && c="$(cat "$MOCK_OPENCODE_COUNT_FILE")"
  c=$((c+1)); echo "$c" > "$MOCK_OPENCODE_COUNT_FILE"
  if [[ "$c" -eq 1 ]]; then
    printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: impl r1\nNEXT: none\nHANDOFF: disputa r1\n'
    exit 0
  fi
fi
[[ -n "${MOCK_OPENCODE_FILE:-}" && -f "$MOCK_OPENCODE_FILE" ]] && { cat "$MOCK_OPENCODE_FILE"; exit 0; }
exit 1
EOF

cat > "$mockbin/agy" <<'EOF'
#!/usr/bin/env bash
# Gate 14B.4.2: el rol se registra por el contenido del prompt que llega por
# stdin (ask-antigravity alimenta `< prompt_file"); si contiene
# "third-party judge" es ÁRBITRO y toca su hit-file (registro inequívoco).
body="$(cat)"
if [[ "$body" == *"third-party judge"* ]]; then
  [[ -n "${MOCK_AGY_JUDGE_HIT:-}" ]] && printf 'judge\n' > "$MOCK_AGY_JUDGE_HIT"
  if [[ -n "${MOCK_AGY_JUDGE_FILE:-}" && -f "$MOCK_AGY_JUDGE_FILE" ]]; then
    cat "$MOCK_AGY_JUDGE_FILE"; exit 0
  fi
fi
# Gate 14B.4.2: contador opcional de invocaciones SIN rol de juez: la 1ª
# (implementador fallback r1) fuerza la disputa; el resto usa el archivo clásico.
if [[ -n "${MOCK_AGY_COUNT_FILE:-}" ]]; then
  c=0; [[ -f "$MOCK_AGY_COUNT_FILE" ]] && c="$(cat "$MOCK_AGY_COUNT_FILE")"
  c=$((c+1)); echo "$c" > "$MOCK_AGY_COUNT_FILE"
  if [[ "$c" -eq 1 ]]; then
    printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: impl r1\nNEXT: none\nHANDOFF: agy impl\n'
    exit 0
  fi
fi
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

# ── caso 11 (Gate 14B.1): modificación conservando tamaño y mtime → detector de contenido la captura ─
rm -rf "$tmp_root/workspace/tamper11"; mkdir -p "$tmp_root/workspace/tamper11"
printf 'PRISTINE-CONTENT' > "$tmp_root/workspace/tamper11/gen.txt"
( cd "$tmp_root/workspace/tamper11" && MOCK_WS="$tmp_root/workspace/tamper11" MOCK_CLAUDE_EFFECT=rewrite_same_meta \
  MOCK_CLAUDE_FILE="$tmp_root/c4c.txt" MOCK_CODEX_FILE="$tmp_root/c4r.txt" AGENT_BRIDGE_HOME="$tmp_root/bridge-tamper11" \
  bash "$engine" "$tmp_root/workspace/tamper11" "tamper same-size mtime" 2 > "$tmp_root/tamper11.full" 2>&1; echo $? > "$tmp_root/tamper11.rc" )
if [[ "$(cat "$tmp_root/tamper11.rc")" -eq 2 ]] && grep -q "objective verification" "$tmp_root/tamper11.full" \
   && grep -q "Done: VERIFY_FAILING" "$tmp_root/tamper11.full" \
   && [[ "$(cat "$tmp_root/workspace/tamper11/gen.txt" 2>/dev/null)" == "GROUND-1-TRUTH-2" ]]; then case_pass same_meta_rewrite_caught; else case_fail same_meta_rewrite_caught "rc2+interchange de contenido detectado" "$(cat "$tmp_root/tamper11.rc")" "" "$tmp_root/tamper11.full"; fi

# ── caso 12 (Gate 14B.1): árbol parcialmente inaccesible → fail-closed (UNRELIABLE), nunca consenso falso ─
rm -rf "$tmp_root/workspace/unread"; mkdir -p "$tmp_root/workspace/unread"
printf 'secret' > "$tmp_root/workspace/unread/locked.txt"; chmod 000 "$tmp_root/workspace/unread/locked.txt"
( cd "$tmp_root/workspace/unread" && MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c1r.txt" AGENT_BRIDGE_HOME="$tmp_root/bridge-unread" \
  bash "$engine" "$tmp_root/workspace/unread" "consenso con ilegible" 2 > "$tmp_root/unread.full" 2>&1; echo $? > "$tmp_root/unread.rc" )
# El snapshot no puede garantizarse: falla cerrada, jamás CONSENSUS rc=0.
unread_rc="$(cat "$tmp_root/unread.rc")"
if [[ "$unread_rc" -ne 0 ]] && ! grep -q "Done: CONSENSUS" "$tmp_root/unread.full"; then case_pass unreadable_tree_fail_closed; else case_fail unreadable_tree_fail_closed "rc!=0 y sin CONSENSUS" "$unread_rc" "" "$tmp_root/unread.full"; fi
chmod 644 "$tmp_root/workspace/unread/locked.txt" 2>/dev/null || true

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

# ── Gate 14B.2: política declarada vacía/ilegible nunca abre permisos ────────
# No se ejecutan agentes si la autorización no se valida: sin línea "Run:".
run_allowlist_case() {
  local label="$1" expected_rc="$2"; shift 2
  local log="$tmp_root/allowlist-$label.log" actual
  (
    cd "$tmp_root"
    env HOME="$HOME_NS" AGENT_BRIDGE_HOME="$tmp_root/bridge-policy-$label" \
      MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c1r.txt" \
      "$@" bash "$engine" "$tmp_root/workspace/clean1" "allowlist $label" 1
  ) >"$log" 2>&1
  actual=$?
  if [[ "$actual" -eq "$expected_rc" ]] && ! grep -q '^Run:' "$log" &&
    grep -q 'Workspace not authorized' "$log"; then
    case_pass "allowlist_$label"
  else
    case_fail "allowlist_$label" "rc=$expected_rc, reject, sin Run" "$actual" "" "$log"
  fi
}
: > "$tmp_root/empty-allowlist"
printf '# solo comentarios\n\n' > "$tmp_root/comments-allowlist"
run_allowlist_case empty_file 7 AGENT_BRIDGE_ALLOWLIST_FILE="$tmp_root/empty-allowlist"
run_allowlist_case comments_only 7 AGENT_BRIDGE_ALLOWLIST_FILE="$tmp_root/comments-allowlist"
run_allowlist_case missing_explicit_file 7 AGENT_BRIDGE_ALLOWLIST_FILE="$tmp_root/not-created"
run_allowlist_case empty_env 7 AGENT_BRIDGE_ALLOWED_WORKSPACES=''
run_allowlist_case separators_only 7 AGENT_BRIDGE_ALLOWED_WORKSPACES=':::'
run_allowlist_case hermes_no_policy 7 AGENT_BRIDGE_REQUIRE_ALLOWLIST=1 \
  AGENT_BRIDGE_ALLOWLIST_FILE="$tmp_root/not-created"
# Modo estricto también debe rechazar si no hay declaración de ningún tipo.
(
  cd "$tmp_root"
  env -u AGENT_BRIDGE_ALLOWED_WORKSPACES -u AGENT_BRIDGE_ALLOWLIST_FILE \
    HOME="$HOME_NS" AGENT_BRIDGE_REQUIRE_ALLOWLIST=1 \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-policy-strict-unconfigured" \
    bash "$engine" "$tmp_root/workspace/clean1" "strict no policy" 1
) > "$tmp_root/strict-unconfigured.log" 2>&1
_rc=$?
if [[ "$_rc" -eq 7 ]] && ! grep -q '^Run:' "$tmp_root/strict-unconfigured.log"; then
  case_pass allowlist_strict_unconfigured
else
  case_fail allowlist_strict_unconfigured "rc7, sin Run" "$_rc" "" "$tmp_root/strict-unconfigured.log"
fi

# ── Gate 14B.3: falla de enumeración de find sobre directorio ilegible ──────
# Caso 13 (findfail_dir_fail_closed): con chmod 000 en un DIRECTORIO find no
# puede descender: la lista del snapshot parece "completa" pero omite todo lo
# que hay dentro (falso negativo silencioso). find termina con rc!=0 → el
# snapshot se declara UNRELIABLE (detección no garantizable). requires no-root.
if [[ "$(id -u)" -eq 0 ]]; then
  case_skip findfail_dir_fail_closed "chmod 000 es readable para root"
else
  rm -rf "$tmp_root/workspace/findfail"; mkdir -p "$tmp_root/workspace/findfail"
  printf 'visible-content' > "$tmp_root/workspace/findfail/ok.txt"
  mkdir "$tmp_root/workspace/findfail/locked"
  printf 'hidden-content' > "$tmp_root/workspace/findfail/locked/child.txt"
  chmod 000 "$tmp_root/workspace/findfail/locked"
  ( cd /tmp && MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c1r.txt" \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-findfail" \
    bash "$engine" "$tmp_root/workspace/findfail" "findfail dir" 2 > "$tmp_root/findfail.full" 2>&1; echo $? > "$tmp_root/findfail.rc" )
  chmod 700 "$tmp_root/workspace/findfail/locked" 2>/dev/null || true
  rc13="$(cat "$tmp_root/findfail.rc")"
  if [[ "$rc13" -eq 2 ]] && grep -q "Done: VERIFY_FAILING" "$tmp_root/findfail.full" \
     && grep -q "consensus REJECTED: workspace snapshot unreliable (detection limit)" "$tmp_root/findfail.full"; then
    case_pass findfail_dir_fail_closed
  else
    case_fail findfail_dir_fail_closed "rc=2+VERIFY_FAILING+rechazo explicito por snapshot no confiable" "$rc13" "" "$tmp_root/findfail.full"
  fi
fi

# ── Caso 14 (Gate 14B.3): UNRELIABLE bloquea CONSENSUS incluso con verify exitoso ──
# Un archivo ilegible (chmod 000) rompe el conteo de hashes → snapshot
# UNRELIABLE (detección no garantizable) + verify exit=0. La verificación del
# ground truth NO restaura la confianza perdida: el consenso se rechaza
# igualmente, fail-closed. requires no-root.
if [[ "$(id -u)" -eq 0 ]]; then
  case_skip unreliable_blocks_consensus_with_verify "chmod 000 es readable para root"
else
  rm -rf "$tmp_root/workspace/unrel"; mkdir -p "$tmp_root/workspace/unrel"
  printf 'readable-content' > "$tmp_root/workspace/unrel/ok.txt"
  printf 'locked-content' > "$tmp_root/workspace/unrel/locked.txt"
  chmod 000 "$tmp_root/workspace/unrel/locked.txt"
  ( cd /tmp && MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c1r.txt" \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-unrel" AGENT_BRIDGE_VERIFY_CMD="echo verify-ok" \
    bash "$engine" "$tmp_root/workspace/unrel" "unreliable" 2 > "$tmp_root/unrel.full" 2>&1; echo $? > "$tmp_root/unrel.rc" )
  chmod 644 "$tmp_root/workspace/unrel/locked.txt" 2>/dev/null || true
  rc14="$(cat "$tmp_root/unrel.rc")"
  if [[ "$rc14" -eq 2 ]] && grep -q "Done: VERIFY_FAILING" "$tmp_root/unrel.full" \
     && grep -q '^  verify: exit=0' "$tmp_root/unrel.full" \
     && grep -q "consensus REJECTED: workspace snapshot unreliable (detection limit)" "$tmp_root/unrel.full"; then
    case_pass unreliable_blocks_consensus_with_verify
  else
    case_fail unreliable_blocks_consensus_with_verify "rc=2+VERIFY_FAILING+verify exit=0+rechazo UNRELIABLE" "$rc14" "" "$tmp_root/unrel.full"
  fi
fi

# ── Gate 14B.4.1 (RT-02): el árbitro MODIFICA el workspace durante call_judge ─
# Caso 15 (judge_ws_write_no_verify_cmd): OpenCode implementa en r1, disputa
# con codex, el ÁRBITRO (2ª invocación de opencode) crea un archivo en el
# workspace y r2 termina en VERIFIED. RED actual: todo queda fuera de las
# ventanas delta → CONSENSUS rc=0 no verificado. GREEN esperado: fail-closed,
# rc=2 + VERIFY_FAILING + rechazo objetivo.
printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: impl r2\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c15impl-r2.txt"
printf 'STATUS: VERIFIED\nCHANGED: none\nEVIDENCE: rev r2\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/c15rev.txt"
rm -rf "$tmp_root/workspace/judge-ws" "$tmp_root/judge15-oc-count" "$tmp_root/judge15-xd-count"
mkdir -p "$tmp_root/workspace/judge-ws"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c15rev.txt" \
    MOCK_OPENCODE_FILE="$tmp_root/c15impl-r2.txt" \
    MOCK_OPENCODE_COUNT_FILE="$tmp_root/judge15-oc-count" MOCK_CODEX_COUNT_FILE="$tmp_root/judge15-xd-count" \
    MOCK_JUDGE_WS_WRITE="$tmp_root/workspace/judge-ws" AGENT_BRIDGE_HOME="$tmp_root/bridge-judge-ws" \
    MOCK_CLAUDE_FAIL=1 MOCK_CODEX_FAIL=""
  bash "$engine" "$tmp_root/workspace/judge-ws" "juez modifica workspace" 2 > "$tmp_root/judge-ws.full" 2>&1
  echo $? > "$tmp_root/judge-ws.rc"
)
rc15="$(cat "$tmp_root/judge-ws.rc")"
tampered=0; [[ -f "$tmp_root/workspace/judge-ws/SNEAKY-BY-JUDGE.txt" ]] && tampered=1
if [[ "$tampered" -ne 1 ]]; then
  case_fail judge_ws_write_no_verify_cmd "el escenario no aplicó: el juez no tocó el workspace (preparación mal formada)" "?" "" "$tmp_root/judge-ws.full"
elif [[ "$rc15" -eq 2 ]] && grep -q "Done: VERIFY_FAILING" "$tmp_root/judge-ws.full" \
     && grep -q "workspace changed without objective verification" "$tmp_root/judge-ws.full" \
     && grep -q "during judge arbitration" "$tmp_root/judge-ws.full"; then
  case_pass judge_ws_write_no_verify_cmd
else
  case_fail judge_ws_write_no_verify_cmd "rc=2+VERIFY_FAILING+rechazo objetivo (RED actual: CONSENSUS rc=0 no verificado)" "$rc15" "" "$tmp_root/judge-ws.full"
fi

# ── Gate 14B.4.1 (RT-02): delta del juez con AGENT_BRIDGE_VERIFY_CMD fallido ──
# Caso 16 (judge_ws_delta_runs_verify): mismo escenario + verify que FALLA.
# El control objetivo del motor debe correr Ground Truth por causa del delta
# del juez: la corrida debe registrar `verify: exit=1` y el marcador VERIFY-RAN,
# y nunca llegar a CONSENSUS (rc=2).
rm -rf "$tmp_root/workspace/judge-ws2" "$tmp_root/judge16-oc-count" "$tmp_root/judge16-xd-count" "$tmp_root/verify-judge16.log"
mkdir -p "$tmp_root/workspace/judge-ws2"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c15rev.txt" \
    MOCK_OPENCODE_FILE="$tmp_root/c15impl-r2.txt" \
    MOCK_OPENCODE_COUNT_FILE="$tmp_root/judge16-oc-count" MOCK_CODEX_COUNT_FILE="$tmp_root/judge16-xd-count" \
    MOCK_JUDGE_WS_WRITE="$tmp_root/workspace/judge-ws2" AGENT_BRIDGE_HOME="$tmp_root/bridge-judge-ws2" \
    MOCK_CLAUDE_FAIL=1 MOCK_CODEX_FAIL="" \
    AGENT_BRIDGE_VERIFY_CMD="echo VERIFY-RAN >> $tmp_root/verify-judge16.log; false"
  bash "$engine" "$tmp_root/workspace/judge-ws2" "delta del juez con verify fallido" 2 > "$tmp_root/judge-ws2.full" 2>&1
  echo $? > "$tmp_root/judge-ws2.rc"
)
rc16="$(cat "$tmp_root/judge-ws2.rc")"
verify_ran=0; [[ -s "$tmp_root/verify-judge16.log" ]] && verify_ran=1
if [[ "$rc16" -eq 2 ]] && grep -q "Done: VERIFY_FAILING" "$tmp_root/judge-ws2.full" \
   && grep -q '^  verify: exit=1' "$tmp_root/judge-ws2.full" \
   && [[ "$verify_ran" -eq 1 ]]; then
  case_pass judge_ws_delta_runs_verify
else
  case_fail judge_ws_delta_runs_verify "rc=2+VERIFY_FAILING+verify exit=1 corrió por delta del juez" "$rc16" "" "$tmp_root/judge-ws2.full"
fi

# Caso 17 (judge_ws_verify_success_continues) [C-REGRESIÓN set -e]: mismo
# escenario de tamper + AGENT_BRIDGE_VERIFY_CMD EXITOSO. Tras run_verify
# exitoso, round_verify_failed=0 y la comparación `[[ 0 -eq 1 ]] && asg`
# del commit a3e1af2 devolvería 1 como ÚLTIMA sentencia de judge_ws_gate()
# → sale 1 → call_judge sale 1 → el aborto prematuro del motor por set -e.
# GREEN esperado: el motor completa sus controles normalmente y continúa
# hasta el estado final objetivo (CONSENSUS rc=0), sin aborto.
rm -rf "$tmp_root/workspace/judge-ws3" "$tmp_root/judge17-oc-count" "$tmp_root/judge17-xd-count" "$tmp_root/verify-judge17.log"
mkdir -p "$tmp_root/workspace/judge-ws3"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c15rev.txt" \
    MOCK_OPENCODE_FILE="$tmp_root/c15impl-r2.txt" \
    MOCK_OPENCODE_COUNT_FILE="$tmp_root/judge17-oc-count" MOCK_CODEX_COUNT_FILE="$tmp_root/judge17-xd-count" \
    MOCK_JUDGE_WS_WRITE="$tmp_root/workspace/judge-ws3" AGENT_BRIDGE_HOME="$tmp_root/bridge-judge-ws3" \
    MOCK_CLAUDE_FAIL=1 MOCK_CODEX_FAIL="" \
    AGENT_BRIDGE_VERIFY_CMD="echo VERIFY-RAN >> $tmp_root/verify-judge17.log; true"
  bash "$engine" "$tmp_root/workspace/judge-ws3" "delta del juez con verify exitoso" 2 > "$tmp_root/judge-ws3.full" 2>&1
  echo $? > "$tmp_root/judge-ws3.rc"
)
rc17="$(cat "$tmp_root/judge-ws3.rc")"
verify17=0; [[ -s "$tmp_root/verify-judge17.log" ]] && verify17=1
tamper17=0; [[ -f "$tmp_root/workspace/judge-ws3/SNEAKY-BY-JUDGE.txt" ]] && tamper17=1
if [[ "$tamper17" -eq 1 && "$rc17" -eq 0 ]] && grep -q "Done: CONSENSUS" "$tmp_root/judge-ws3.full" \
   && grep -q '^  verify: exit=0' "$tmp_root/judge-ws3.full" && [[ "$verify17" -eq 1 ]] \
   && grep -q "GROUND TRUTH after judge (round" "$tmp_root/judge-ws3.full"; then
  case_pass judge_ws_verify_success_continues
else
  case_fail judge_ws_verify_success_continues "rc=0+CONSENSUS+verify exit=0 sin aborto prematuro (RED: aborto de set -e tras verify del juez exitoso)" "$rc17" "" "$tmp_root/judge-ws3.full"
fi

# Caso 18 (judge_ws_unreliable_with_verify_success) [C-REGRESIÓN]: snapshot
# no confiable DURANTE el arbitraje (el juez deja un archivo chmod 000 que
# rompe el hash del snapshot post) con verify exitoso. La pérdida de
# confianza no se restaura por un exit=0 de ground truth: rechazo
# obligatorio de CONSENSUS por VERIFY_FAILING rc=2.
rm -rf "$tmp_root/workspace/judge-ws4" "$tmp_root/judge18-oc-count" "$tmp_root/judge18-xd-count" "$tmp_root/verify-judge18.log"
mkdir -p "$tmp_root/workspace/judge-ws4"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c15rev.txt" \
    MOCK_OPENCODE_FILE="$tmp_root/c15impl-r2.txt" \
    MOCK_OPENCODE_COUNT_FILE="$tmp_root/judge18-oc-count" MOCK_CODEX_COUNT_FILE="$tmp_root/judge18-xd-count" \
    MOCK_JUDGE_WS_WRITE="$tmp_root/workspace/judge-ws4" MOCK_JUDGE_WS_UNREAD=1 \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-judge-ws4" \
    MOCK_CLAUDE_FAIL=1 MOCK_CODEX_FAIL="" \
    AGENT_BRIDGE_VERIFY_CMD="echo VERIFY-RAN >> $tmp_root/verify-judge18.log; true"
  bash "$engine" "$tmp_root/workspace/judge-ws4" "juez deja snapshot no confiable" 2 > "$tmp_root/judge-ws4.full" 2>&1
  echo $? > "$tmp_root/judge-ws4.rc"
)
chmod 644 "$tmp_root/workspace/judge-ws4/LOCKED-BY-JUDGE.txt" 2>/dev/null || true
rc18="$(cat "$tmp_root/judge-ws4.rc")"
locked=0; [[ -f "$tmp_root/workspace/judge-ws4/LOCKED-BY-JUDGE.txt" ]] && locked=1
if [[ "$locked" -eq 1 && "$rc18" -eq 2 ]] && grep -q "Done: VERIFY_FAILING" "$tmp_root/judge-ws4.full" \
   && grep -q "consensus REJECTED: workspace snapshot unreliable (detection limit)" "$tmp_root/judge-ws4.full" \
   && grep -q '^  verify: exit=0' "$tmp_root/judge-ws4.full"; then
  case_pass judge_ws_unreliable_with_verify_success
else
  case_fail judge_ws_unreliable_with_verify_success "rc=2+VERIFY_FAILING+UNRELIABLE tras snapshot del juez, verify exit=0 no lo restaura (RED: aborto de set -e)" "$rc18" "" "$tmp_root/judge-ws4.full"
fi

# ══ Gate 14B.4.2 (RT-01a): independencia del ÁRBITRO vs implementador y revisor ══
# Registro de rol: cada mock escribe su hit-file SOLO cuando se ejecuta con el
# prompt del árbitro ("third-party judge"), de modo que la prueba valida la
# identidad real del proveedor, no que el motor termine con un código dado.
# Protocolos válidos de árbitro por proveedor (marcador inequívoco en HANDOFF).
printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: impl dispute\nNEXT: none\nHANDOFF: disputa impl\n' > "$tmp_root/rt01a-impl-dispute.txt"
printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: impl dispute\nNEXT: none\nHANDOFF: disputa claude\n' > "$tmp_root/rt01a-impl-claude.txt"
printf 'STATUS: PROPOSED\nCHANGED: none\nEVIDENCE: impl r2\nNEXT: none\nHANDOFF: ok\n' > "$tmp_root/rt01a-impl-agy-r2.txt"
printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: rev oc\nNEXT: none\nHANDOFF: disputa rev oc\n' > "$tmp_root/rt01a-rev-oc.txt"
printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: rev agy\nNEXT: none\nHANDOFF: disputa rev agy\n' > "$tmp_root/rt01a-rev-agy.txt"
printf 'STATUS: DISAGREE\nCHANGED: none\nEVIDENCE: arbiter\nNEXT: none\nHANDOFF: arbiter-agy-marker\nVERDICT: REQUEST_REVISION\n' > "$tmp_root/rt01a-agy-judge.txt"

# ── Caso 19 (rt01a_agy_arbitrates_when_oc_implemented): OpenCode implementa,
# Codex revisa. OpenCode NO puede arbitrar; debe seleccionarse AGY.
# RED (engine actual): opencode se auto-arbitra → hit de arbiter opencode.
rm -rf "$tmp_root/workspace/rt01a-ws1" "$tmp_root/rt01a-1-oc-count" "$tmp_root/rt01a-1-xd-count" "$tmp_root/hit-oc-judge-1" "$tmp_root/hit-agy-judge-1"
mkdir -p "$tmp_root/workspace/rt01a-ws1"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c15rev.txt" \
    MOCK_CLAUDE_FAIL=1 MOCK_CODEX_FAIL="" \
    MOCK_OPENCODE_FILE="$tmp_root/rt01a-impl-dispute.txt" \
    MOCK_OPENCODE_COUNT_FILE="$tmp_root/rt01a-1-oc-count" MOCK_CODEX_COUNT_FILE="$tmp_root/rt01a-1-xd-count" \
    MOCK_AGY_JUDGE_FILE="$tmp_root/rt01a-agy-judge.txt" \
    MOCK_OPENCODE_JUDGE_HIT="$tmp_root/hit-oc-judge-1" MOCK_AGY_JUDGE_HIT="$tmp_root/hit-agy-judge-1" \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-rt01a-1"
  bash "$engine" "$tmp_root/workspace/rt01a-ws1" "RT-01a: impl opencode, rev codex" 2 > "$tmp_root/rt01a-1.full" 2>&1
  echo $? > "$tmp_root/rt01a-1.rc"
)
rcN1="$(cat "$tmp_root/rt01a-1.rc")"
agy_hit_1=0; [[ -f "$tmp_root/hit-agy-judge-1" ]] && agy_hit_1=1
oc_hit_1=0; [[ -f "$tmp_root/hit-oc-judge-1" ]] && oc_hit_1=1
if [[ "$agy_hit_1" -eq 1 && "$oc_hit_1" -eq 0 ]] \
   && grep -q "Implementer (opencode)" "$tmp_root/rt01a-1.full" \
   && grep -q "judge: OpenCode excluded (independence: implemented/reviewed this round)" "$tmp_root/rt01a-1.full" \
   && grep -q "HANDOFF: arbiter-agy-marker" "$tmp_root/rt01a-1.full"; then
  case_pass rt01a_agy_arbitrates_when_oc_implemented
else
  case_fail rt01a_agy_arbitrates_when_oc_implemented "opencode implementó y no puede arbitrar (RED: opencode se auto-arbitró)" "$rcN1" "agy_hit=$agy_hit_1 oc_hit=$oc_hit_1" "$tmp_root/rt01a-1.full"
fi

# ── Caso 20 (rt01a_oc_arbitrates_when_agy_implemented): AGY implementa vía
# AGENT_BRIDGE_FALLBACKS="agy" (OpenCode nunca falló: sigue disponible), Codex
# revisa. OpenCode es independiente y precede como candidato: debe arbitrar.
rm -rf "$tmp_root/workspace/rt01a-ws2" "$tmp_root/rt01a-2-gy-count" "$tmp_root/rt01a-2-xd-count" "$tmp_root/hit-oc-judge-2" "$tmp_root/hit-agy-judge-2"
mkdir -p "$tmp_root/workspace/rt01a-ws2"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CODEX_FILE="$tmp_root/c15rev.txt" \
    MOCK_CLAUDE_FAIL=1 MOCK_CODEX_FAIL="" \
    AGENT_BRIDGE_FALLBACKS="agy" \
    MOCK_AGY_FILE="$tmp_root/rt01a-impl-agy-r2.txt" \
    MOCK_AGY_COUNT_FILE="$tmp_root/rt01a-2-gy-count" MOCK_CODEX_COUNT_FILE="$tmp_root/rt01a-2-xd-count" \
    MOCK_OPENCODE_JUDGE_HIT="$tmp_root/hit-oc-judge-2" MOCK_AGY_JUDGE_HIT="$tmp_root/hit-agy-judge-2" \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-rt01a-2"
  bash "$engine" "$tmp_root/workspace/rt01a-ws2" "RT-01a: impl agy, rev codex" 2 > "$tmp_root/rt01a-2.full" 2>&1
  echo $? > "$tmp_root/rt01a-2.rc"
)
rcN2="$(cat "$tmp_root/rt01a-2.rc")"
agy_hit_2=0; [[ -f "$tmp_root/hit-agy-judge-2" ]] && agy_hit_2=1
oc_hit_2=0; [[ -f "$tmp_root/hit-oc-judge-2" ]] && oc_hit_2=1
if [[ "$oc_hit_2" -eq 1 && "$agy_hit_2" -eq 0 ]] \
   && grep -q "Implementer (agy)" "$tmp_root/rt01a-2.full" \
   && grep -q "escalating to OpenCode judge" "$tmp_root/rt01a-2.full" \
   && grep -q "Done: CONSENSUS" "$tmp_root/rt01a-2.full" && [[ "$rcN2" -eq 0 ]]; then
  case_pass rt01a_oc_arbitrates_when_agy_implemented
else
  case_fail rt01a_oc_arbitrates_when_agy_implemented "agy implementó y no puede arbitrar; opcode disponible debe preceder (RED: mismo estado actual esperado)" "$rcN2" "agy_hit=$agy_hit_2 oc_hit=$oc_hit_2" "$tmp_root/rt01a-2.full"
fi

# ── Caso 21 (rt01a_no_independent_judge_failclosed): OpenCode implementa,
# AGY revisa (codex falla). Ningún candidato independiente permanece: el
# arbitraje DEBE rechazarse con estado explícito NO_INDEPENDENT_JUDGE rc=8,
# sin árbitro ejecutado y sin continuar hacia un consenso posterior.
rm -rf "$tmp_root/workspace/rt01a-ws3" "$tmp_root/rt01a-3-oc-count" "$tmp_root/hit-oc-judge-3" "$tmp_root/hit-agy-judge-3"
mkdir -p "$tmp_root/workspace/rt01a-ws3"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/c1c.txt" MOCK_CLAUDE_FAIL=1 MOCK_CODEX_FAIL=1 \
    MOCK_OPENCODE_FILE="$tmp_root/rt01a-impl-dispute.txt" \
    MOCK_OPENCODE_COUNT_FILE="$tmp_root/rt01a-3-oc-count" \
    MOCK_AGY_FILE="$tmp_root/rt01a-rev-agy.txt" \
    MOCK_OPENCODE_JUDGE_HIT="$tmp_root/hit-oc-judge-3" MOCK_AGY_JUDGE_HIT="$tmp_root/hit-agy-judge-3" \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-rt01a-3"
  bash "$engine" "$tmp_root/workspace/rt01a-ws3" "RT-01a: sin candidato independiente" 2 > "$tmp_root/rt01a-3.full" 2>&1
  echo $? > "$tmp_root/rt01a-3.rc"
)
rcN3="$(cat "$tmp_root/rt01a-3.rc")"
agy_hit_3=0; [[ -f "$tmp_root/hit-agy-judge-3" ]] && agy_hit_3=1
oc_hit_3=0; [[ -f "$tmp_root/hit-oc-judge-3" ]] && oc_hit_3=1
if [[ "$rcN3" -eq 8 ]] && grep -q "Done: NO_INDEPENDENT_JUDGE" "$tmp_root/rt01a-3.full" \
   && grep -q "no candidate is independent of implementer 'opencode' and reviewer 'agy'" "$tmp_root/rt01a-3.full" \
   && grep -q "Implementer (opencode)" "$tmp_root/rt01a-3.full" \
   && grep -q "Reviewer (agy)" "$tmp_root/rt01a-3.full" \
   && [[ "$oc_hit_3" -eq 0 && "$agy_hit_3" -eq 0 ]]; then
  case_pass rt01a_no_independent_judge_failclosed
else
  case_fail rt01a_no_independent_judge_failclosed "rc=8+NO_INDEPENDENT_JUDGE sin árbitro ejecutado (RED: opencode se auto-arbitró y la corrida continuó)" "$rcN3" "agy_hit=$agy_hit_3 oc_hit=$oc_hit_3" "$tmp_root/rt01a-3.full"
fi

# ── Caso 22 (rt01a_agy_arbitrates_when_oc_reviewed): Claude implementa,
# Codex falla y OpenCode revisa (excluye a claude por independencia). El
# árbitro debe excluir también al REVISOR: opencode no puede arbitrar, AGY sí.
rm -rf "$tmp_root/workspace/rt01a-ws4" "$tmp_root/hit-oc-judge-4" "$tmp_root/hit-agy-judge-4"
mkdir -p "$tmp_root/workspace/rt01a-ws4"
( cd /tmp
  export MOCK_CLAUDE_FILE="$tmp_root/rt01a-impl-claude.txt" MOCK_CODEX_FAIL=1 \
    MOCK_OPENCODE_FILE="$tmp_root/rt01a-rev-oc.txt" \
    MOCK_AGY_JUDGE_FILE="$tmp_root/rt01a-agy-judge.txt" \
    MOCK_OPENCODE_JUDGE_HIT="$tmp_root/hit-oc-judge-4" MOCK_AGY_JUDGE_HIT="$tmp_root/hit-agy-judge-4" \
    AGENT_BRIDGE_HOME="$tmp_root/bridge-rt01a-4"
  bash "$engine" "$tmp_root/workspace/rt01a-ws4" "RT-01a: impl claude, rev opencode" 2 > "$tmp_root/rt01a-4.full" 2>&1
  echo $? > "$tmp_root/rt01a-4.rc"
)
rcN4="$(cat "$tmp_root/rt01a-4.rc")"
agy_hit_4=0; [[ -f "$tmp_root/hit-agy-judge-4" ]] && agy_hit_4=1
oc_hit_4=0; [[ -f "$tmp_root/hit-oc-judge-4" ]] && oc_hit_4=1
if [[ "$agy_hit_4" -eq 1 && "$oc_hit_4" -eq 0 ]] \
   && grep -q "Reviewer (opencode)" "$tmp_root/rt01a-4.full" \
   && grep -q "judge: OpenCode excluded (independence: implemented/reviewed this round)" "$tmp_root/rt01a-4.full" \
   && grep -q "HANDOFF: arbiter-agy-marker" "$tmp_root/rt01a-4.full" \
   && grep -q "Done: MAX_ROUNDS" "$tmp_root/rt01a-4.full"; then
  case_pass rt01a_agy_arbitrates_when_oc_reviewed
else
  case_fail rt01a_agy_arbitrates_when_oc_reviewed "opencode revisó y no puede arbitrar (RED: opencode se auto-arbitró como revisor)" "$rcN4" "agy_hit=$agy_hit_4 oc_hit=$oc_hit_4" "$tmp_root/rt01a-4.full"
fi

if [[ $ok_count -eq $total ]]; then
  echo "redteam-gate14b: ok ($ok_count casos; id -u = $(id -u)${skip_count:+, $skip_count omitidos por privilegio})"
  exit 0
fi
echo "redteam-gate14b: $ok_count/$total casos pasaron (omitidos: $skip_count)"
exit 1
