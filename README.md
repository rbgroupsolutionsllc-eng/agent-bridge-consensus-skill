# Agent Bridge Consensus Skill

Portable skill and local bridge protocol for coordinating Claude Code, Codex, and optionally OpenCode as a compact multi-agent team.

## What It Does

- Claude acts as implementer or planner.
- Codex acts as reviewer, verifier, and second implementer.
- OpenCode acts as third-party judge only when there is disagreement or a blocker.
- All agents use compact handoffs to reduce token usage.

## Install Locally

```bash
./bin/install-local
```

This installs the skill into:

```text
~/.codex/skills/agent-bridge-consensus/SKILL.md
~/.claude/skills/agent-bridge-consensus/SKILL.md
```

It also appends an OpenCode judge note to:

```text
~/.config/opencode/AGENTS.md
```

## Use

```bash
agent-turns /path/to/project "shared goal" 2
```

With ground-truth verification:

```bash
AGENT_BRIDGE_VERIFY_CMD="pytest -q" agent-turns /path/to/project "shared goal" 2
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

Final states:

```text
CONSENSUS | BLOCKED | VERIFY_FAILING | CLAUDE_ERROR | CODEX_ERROR | MAX_ROUNDS
```
