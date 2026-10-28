---
name: agent-bridge-consensus
description: Coordinate Claude Code, Codex, OpenCode, and Antigravity as a local multi-agent team with automatic provider fallback.
---

# Agent Bridge Consensus

Use this skill to run or participate in a local Claude/Codex/OpenCode/Antigravity bridge.

## Default Roles

Default profile `AGENT_BRIDGE_ROLES=v2`:

- Claude: initial planner (PLAN, once, before round 1) and independent auditor of the implementation (AUDIT, every round). Claude is read-only in both roles: any workspace change by Claude is a role violation and ends the run `VERIFY_FAILING`.
- Codex: primary implementer.
- `agy` (Antigravity terminal CLI): primary third-party judge. Default model: `Gemini 3.5 Flash (Medium)`.
- OpenCode: alternate judge, only if `agy` is unavailable or excluded for independence; also first automatic fallback for implementer/auditor. Default model: `opencode-go/minimax-m3`.

`AGENT_BRIDGE_ROLES=legacy` keeps the historical arrangement (Claude implements, Codex reviews, OpenCode judges) for regression only.

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

- `1`: Claude plans, Codex implements, Claude audits.
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

1. Claude produces the PLAN (read-only). If Claude cannot plan, the run fails closed (`PLANNER_ERROR`).
2. Codex implements.
3. Claude audits the implementation independently (read-only).
4. If the audit verifies and nothing else blocks, stop.
5. If the auditor disagrees, Codex revises or defends once.
6. If disagreement persists, call `agy` as judge; OpenCode only if `agy` is unavailable or excluded. Verdicts (contract `abc-verdicts/2`): `ACCEPT_IMPLEMENTER | ACCEPT_REVIEWER | REQUEST_REVISION | BLOCKED`; the old `ACCEPT_CLAUDE`/`ACCEPT_CODEX` are rejected, never reinterpreted.
7. If Codex or Claude is unavailable for their role, try OpenCode and then Antigravity automatically (never a participant of the same round as judge).
8. A provider that already served as implementer this round is excluded from reviewer fallback selection the same round — it can never review its own implementation. If no distinct supported fallback reviewer is configured after excluding the implementer, the run fails closed (`NO_INDEPENDENT_REVIEWER`) instead of declaring consensus. If the primary auditor fails and distinct supported fallback reviewer candidates existed but were unavailable or all failed validation or execution, the run fails closed (`CODEX_ERROR`) instead of declaring consensus.

## Token Budget

- Simple: 1 round.
- Normal: 2 rounds.
- Complex: 3 rounds, OpenCode only on disagreement.

The orchestrator only propagates the 5 protocol fields from recent turns. Do not paste logs; reference files in the run artifacts directory.

Final states are `CONSENSUS`, `BLOCKED`, `VERIFY_FAILING`, `IMPLEMENTER_ERROR` (`CLAUDE_ERROR` in legacy), `REVIEWER_ERROR` (`CODEX_ERROR` in legacy), `PLANNER_ERROR`, `NO_INDEPENDENT_REVIEWER`, and `MAX_ROUNDS`. `NO_INDEPENDENT_REVIEWER` means no distinct supported fallback reviewer is configured after excluding the implementer. `REVIEWER_ERROR` covers primary auditor failure when distinct supported fallback reviewer candidates existed but were unavailable or all failed validation or execution. Both paths fail closed and neither emits `CONSENSUS`.
