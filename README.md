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

For lower token use:

```bash
AGENT_BRIDGE_MAX_SUMMARY_CHARS=2000 agent-turns /path/to/project "shared goal" 2
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
