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

Both OpenCode and `agy` enforce model selection via `--model`. Run `opencode models` or `agy models` to list available options. The GUI app (`antigravity`) is not used.

Any provider that fails (any exit code, timeout, or empty response) is automatically marked unavailable for the rest of the session. The fallback chain retries remaining providers without operator intervention.

**Independent review enforcement:** the orchestrator tracks the actual provider identity (not role labels, filenames, PIDs, response content, or call order) that fulfilled the implementer role each round. That identity is excluded from reviewer fallback selection for the same round — a provider can never review its own implementation. If no distinct provider identity remains to serve as reviewer (all other fallbacks failed or the only fallback already implemented), the run fails closed as `NO_INDEPENDENT_REVIEWER` rather than emitting `CONSENSUS`. This exclusion is round-scoped only: an excluded provider is not marked failed and remains eligible in later rounds or other roles.

Final states:

```text
CONSENSUS | BLOCKED | VERIFY_FAILING | CLAUDE_ERROR | CODEX_ERROR | NO_INDEPENDENT_REVIEWER | MAX_ROUNDS
```
