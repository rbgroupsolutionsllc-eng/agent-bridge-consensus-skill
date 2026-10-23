# Agent Bridge Consensus Skill

Portable skill and local bridge protocol for coordinating Claude Code, Codex, OpenCode, and Antigravity as a compact multi-agent team.

## What It Does

- Claude acts as implementer or planner.
- Codex acts as reviewer, verifier, and second implementer.
- OpenCode acts as third-party judge and the first automatic fallback, using MiniMax M3 by default.
- `agy` (Antigravity terminal CLI) is the second automatic fallback and judge fallback.
- Any agent that fails (rate limit, timeout, error) is marked unavailable for the rest of the session and skipped automatically.
- All agents use compact handoffs to reduce token usage.

## Install Locally

Prerequisite: Python 3 is required by `install-local`. The installer checks for `python3` before modifying the installation.

```bash
./bin/install-local
```

This installs the skill into:

```text
~/.codex/skills/agent-bridge-consensus/SKILL.md
~/.claude/skills/agent-bridge-consensus/SKILL.md
~/.local/share/agent-bridge/SKILL.md
```

The third copy is a shared reference file. `agy` has no native skills directory, so `ask-antigravity` passes it via `--add-dir` on every call, when the directory exists.

It also rewrites the OpenCode judge note in:

```text
~/.config/opencode/AGENTS.md
```

Re-running `install-local` always replaces the `## Agent Bridge Consensus` section with the current one from this repo — the install is idempotent, not append-once.

## Use

```bash
agent-turns /path/to/project "shared goal" 2
```

With ground-truth verification:

```bash
AGENT_BRIDGE_VERIFY_CMD="pytest -q" agent-turns /path/to/project "shared goal" 2
```

Specifying models inline in the goal (stripped before agents see the goal):

```bash
agent-turns /path/to/project "refactor auth module [opencode:anthropic/claude-opus-4-8] [agy:Gemini 3.1 Pro (High)]" 2
```

## Compact Protocol

```text
STATUS: PROPOSED | VERIFIED | DISAGREE | REVISE | BLOCKED | COMPLETE
CHANGED: files or "none"
EVIDENCE: command/result or "not run"
NEXT: one concrete next action or "none"
HANDOFF: one sentence to the next agent
```

## Consensus Rule

One agent should not close its own unverified implementation. The other agent verifies. OpenCode arbitrates only when disagreement persists.

## Environment

| Var | Default | Use |
|---|---:|---|
| `AGENT_BRIDGE_HOME` | `~/agent-bridge` | Run artifacts directory |
| `AGENT_BRIDGE_TIMEOUT` | `900` | Seconds per agent turn |
| `AGENT_BRIDGE_VERIFY_CMD` | empty | Ground-truth command after changed turns |
| `AGENT_BRIDGE_VERIFY_TIMEOUT` | `300` | Seconds for verify command |
| `AGENT_BRIDGE_HISTORY_TURNS` | `2`, or `4` when verify is enabled | Recent protocol sections retained |
| `AGENT_BRIDGE_RESUME` | `1` | Claude session resume and cost tracking when `jq` exists |
| `AGENT_BRIDGE_CODEX_RESUME` | `0` | Codex resume via recent CLI |
| `AGENT_BRIDGE_MAX_FALLBACK_CHARS` | `1200` | Fallback when an agent ignores protocol |
| `AGENT_BRIDGE_FALLBACKS` | `opencode,agy` | Ordered automatic fallback providers (`antigravity` is accepted as an alias) |
| `AGENT_BRIDGE_OPENCODE_MODEL` | `opencode-go/minimax-m3` | OpenCode model selected per task |
| `AGENT_BRIDGE_OPENCODE_VARIANT` | empty | Optional OpenCode reasoning variant |
| `AGENT_BRIDGE_ANTIGRAVITY_MODEL` | `Gemini 3.5 Flash (Medium)` | Model passed to `agy --model`; inline: `[agy:model]` |
| `AGENT_BRIDGE_ALLOWED_WORKSPACES` | empty | Gate 14B: authorized workspaces, entries separated by `:` or newlines (canonical paths compared after symlink resolution) |
| `AGENT_BRIDGE_ALLOWLIST_FILE` | `~/.agent-bridge/authorized-workspaces` | Gate 14B: allowlist file (one path per line, `#` comments); used when the env var is unset |

**Workspace authorization (Gate 14B.2):** If `AGENT_BRIDGE_ALLOWED_WORKSPACES` is explicitly set, even to an empty string, it is authoritative and an empty or invalid list is rejected (exit 7). Otherwise, an explicitly selected allowlist file or an existing default file is mandatory to read and must contain at least one authorized path; missing, unreadable, empty, or comment-only policies are rejected (exit 7). Set `AGENT_BRIDGE_REQUIRE_ALLOWLIST=1` for Hermes or other autonomous use: without a valid policy, the bridge rejects execution. Only legacy CLI with no policy configured and strict mode off retains permissive behavior with a warning. Workspace allowlisting is **not** an OS sandbox.

Both OpenCode and `agy` enforce model selection via `--model`. Run `opencode models` or `agy models` to list available options. The GUI app (`antigravity`) is not used.

Any provider that fails (any exit code, timeout, or empty response) is automatically marked unavailable for the rest of the session. The fallback chain retries remaining providers without operator intervention.

**Independent review enforcement:** the orchestrator tracks the actual provider identity (not role labels, filenames, PIDs, response content, or call order) that fulfilled the implementer role each round. That identity is excluded from reviewer fallback selection for the same round — a provider can never review its own implementation. If no distinct supported fallback reviewer is configured after excluding the implementer, the run fails closed as `NO_INDEPENDENT_REVIEWER` rather than emitting `CONSENSUS`. If primary Codex fails and distinct supported fallback reviewer candidates existed but were unavailable or all failed validation or execution, the run fails closed as `CODEX_ERROR` rather than emitting `CONSENSUS`. This exclusion is round-scoped only: an excluded provider is not marked failed and remains eligible in later rounds or other roles.

**Independent judge enforcement (Gate 14B.4.2):** when a dispute requires arbitration, the orchestrator excludes both `impl_provider` and `review_provider` of the current round (actual provider identities, normalized) from arbiter selection. OpenCode remains the preferred arbiter; AGY is used when OpenCode is excluded or unavailable. An excluded provider is never invoked as arbiter (not even as last resort) and is never marked failed by the exclusion. If both arbiter candidates are excluded this way, the run stops immediately with `NO_INDEPENDENT_JUDGE` (exit `8`) instead of continuing toward a possible later consensus; `NO_INDEPENDENT_JUDGE` is used exclusively for participation-based exclusion. If an independent candidate exists but is marked failed or unavailable for the round, the run keeps the existing `JUDGE UNAVAILABLE` path instead of reporting `NO_INDEPENDENT_JUDGE`. A provider is never both the implementer or reviewer and the arbiter of the same round.

Final states:

```text
CONSENSUS | BLOCKED | VERIFY_FAILING | CLAUDE_ERROR | CODEX_ERROR | NO_INDEPENDENT_REVIEWER | NO_INDEPENDENT_JUDGE | MAX_ROUNDS
```

## Exit codes (Gate 14B)

| Code | Meaning |
|---:|---|
| `0` | `CONSENSUS`: the loop reached independently-verified agreement |
| `1` | `MAX_ROUNDS`, or an unmapped internal state |
| `2` | `VERIFY_FAILING`: ground truth failed, or the workspace changed without objective verification |
| `3` | `BLOCKED`: round-1 reviewer reported BLOCKED |
| `4` | `CLAUDE_ERROR`: implementer (and fallbacks) failed or were protocol-invalid |
| `5` | `CODEX_ERROR`: reviewer (and fallbacks) failed or were protocol-invalid |
| `6` | `NO_INDEPENDENT_REVIEWER`: no distinct reviewer provider exists for this round |
| `8` | `NO_INDEPENDENT_JUDGE`: no arbiter candidate is independent of this round's implementer and reviewer (Gate 14B.4.2) |
| `2` (usage) | invalid invocation (bad arguments) |
| `7` | workspace not authorized by `AGENT_BRIDGE_ALLOWED_WORKSPACES` / `AGENT_BRIDGE_ALLOWLIST_FILE` |

## Workspace integrity policy (Gate 14B)

- Primary Claude/Codex responses must satisfy the strict structural protocol validation (same rules as fallbacks): duplicates, missing fields, invalid `STATUS` values and narration outside the protocol are rejected and the role goes through the independent fallback flow, which can never end in `CONSENSUS` from an invalid primary answer.
- The orchestrator snapshots the workspace (files, symlinks, directories; creation, modification, deletion and symlink retargeting are detected) for each agent turn regardless of the declared `CHANGED:` value. A real delta always triggers the ground-truth `AGENT_BRIDGE_VERIFY_CMD` when configured.
- If the workspace changed during the run and no `AGENT_BRIDGE_VERIFY_CMD` is configured, `CONSENSUS` is refused (the run ends `VERIFY_FAILING`): code-modification tasks cannot conclude without objective verification of the final state.
- `AGENT_BRIDGE_VERIFY_CMD` comes exclusively from operator environment variables; model-provided commands are never executed as verification.
- Snapshot detection is same-filesystem (`-xdev`) and conservative (`-printf`/GNU `find`, plus `sha256sum` or `shasum`). If the workspace cannot be snapshotted reliably, the run fails closed: any consensus requires the configured `AGENT_BRIDGE_VERIFY_CMD`.
- Allowlist matching is canonicalized via `os.path.realpath` (symlinks and equivalent paths resolve to one identity). Without an allowlist the CLI behaves as before (stderr warning); the future Hermes mode must set the allowlist. `agent-turns` never grants write/execute by mere existence — the allowlist is the only gate.
- Unreachable/detection limits are reported in `handoff.md` notes (`VERIFY REQUIRED`, snapshot-unreliable) instead of silently proceeding.
