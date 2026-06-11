---
name: agent-bridge-consensus
description: Coordinate Claude Code, Codex, and optionally OpenCode as a local multi-agent team. Use when the user wants agents to talk, take turns, invoke each other, review each other, resolve disagreements, conserve tokens with compact handoffs, or reach a shared goal through consensus.
---

# Agent Bridge Consensus

Use this skill to run or participate in a local Claude/Codex/OpenCode bridge.

## Default Roles

- Claude: first implementer or planner.
- Codex: reviewer, verifier, and second implementer.
- OpenCode: third-party judge only when there is persistent disagreement, `BLOCKED`, or the user asks for arbitration.

Do not call OpenCode by default. Use it only when needed to save tokens.

## Compact Protocol

Every bridge response should be short and use this shape:

```text
STATUS: PROPOSED | VERIFIED | DISAGREE | REVISE | BLOCKED | COMPLETE
CHANGED: files or "none"
EVIDENCE: command/result or "not run"
NEXT: one concrete next action or "none"
HANDOFF: one sentence to the next agent
```

Rules:

- Keep bridge responses to 12 lines or fewer.
- Prefer evidence over explanation.
- Do not mark `COMPLETE` for your own unverified implementation unless the task only asks for a direct answer.
- If disagreeing, write `DISAGREE` with one concrete reason and one proposed correction.
- If revising after disagreement, write `REVISE` and include the evidence.

## Running Turn Taking

Use:

```bash
agent-turns /path/to/project "shared goal" 2
```

For lower token use:

```bash
AGENT_BRIDGE_MAX_SUMMARY_CHARS=2000 agent-turns /path/to/project "shared goal" 2
```

Round guidance:

- `1`: Claude works, Codex reviews.
- `2`: enough for most fixes.
- `3+`: only for complex tasks or unresolved disagreement.

## Direct Agent Calls

Claude:

```bash
ask-claude /path/to/project prompt.md output.md
```

Codex:

```bash
ask-codex /path/to/project prompt.md output.md
```

OpenCode judge:

```bash
ask-opencode /path/to/project prompt.md output.md
```

## Consensus Workflow

1. Let Claude implement or propose.
2. Let Codex verify.
3. If Codex verifies, stop.
4. If Codex disagrees, let Claude revise or defend once.
5. If disagreement persists, call OpenCode as judge.
6. After judge verdict, one agent makes the smallest needed change and the other verifies.

## Token Budget

- Simple: 1 round, compact summary 2000 chars.
- Normal: 2 rounds, compact summary 2000-4000 chars.
- Complex: 3 rounds, OpenCode only on disagreement.

Avoid pasting full logs. Summarize with changed files, commands run, and results.
