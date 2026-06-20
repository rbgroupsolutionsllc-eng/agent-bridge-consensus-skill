---
name: agent-bridge-consensus
description: Coordinate Claude Code, Codex, OpenCode, and Antigravity as a local multi-agent team with automatic provider fallback.
---

# Agent Bridge Consensus

Use this skill to run or participate in a local Claude/Codex/OpenCode/Antigravity bridge.

## Default Roles

- Claude: first implementer or planner.
- Codex: reviewer, verifier, and second implementer.
- OpenCode: third-party judge and first automatic fallback. Default model: `opencode-go/minimax-m3`.
- `agy` (Antigravity terminal CLI): second automatic fallback and judge fallback. Default model: `Gemini 3.5 Flash (Medium)`.

Any agent that fails (rate limit, timeout, error) is marked unavailable for the session and skipped automatically. No operator intervention needed.

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

For ground-truth verification after changed turns:

```bash
AGENT_BRIDGE_VERIFY_CMD="pytest -q" agent-turns /path/to/project "shared goal" 2
```

To specify models inline (directives are stripped from the goal before agents see it):

```bash
agent-turns /path/to/project "goal [opencode:anthropic/claude-opus-4-8] [agy:Gemini 3.1 Pro (High)]" 2
```

If the ground-truth command fails, the orchestrator rejects `VERIFIED` or `COMPLETE` for that round and continues until the command passes or rounds are exhausted.

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

Antigravity fallback:

```bash
ask-antigravity /path/to/project prompt.md output.md
```

OpenCode and `agy` both enforce model selection via `--model`. Run `opencode models` or `agy models` for available options. Inline directives `[opencode:model]` and `[agy:model]` in the goal override env vars.

## Consensus Workflow

1. Let Claude implement or propose.
2. Let Codex verify.
3. If Codex verifies, stop.
4. If Codex disagrees, let Claude revise or defend once.
5. If disagreement persists, call OpenCode as judge.
6. After judge verdict, one agent makes the smallest needed change and the other verifies.
7. If Claude or Codex is unavailable, try OpenCode and then Antigravity automatically.

## Token Budget

- Simple: 1 round.
- Normal: 2 rounds.
- Complex: 3 rounds, OpenCode only on disagreement.

The orchestrator only propagates the 5 protocol fields from recent turns. Do not paste logs; reference files in the run artifacts directory.

Final states are `CONSENSUS`, `BLOCKED`, `VERIFY_FAILING`, `CLAUDE_ERROR`, `CODEX_ERROR`, and `MAX_ROUNDS`.
