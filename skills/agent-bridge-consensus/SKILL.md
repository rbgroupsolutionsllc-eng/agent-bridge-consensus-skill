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

## Inline Directives & Cognitive Knobs (v3.5)

You can pass cognitive modes and model directives directly inside the goal string:

```bash
agent-turns /path/to/project "corrige el memory leak [OODA] [REDTEAM] [x10think]" 2
```

### Cognitive Knobs:
- **`[OODA]`**: Enforces Observe -> Orient -> Decide -> Act cycle before mutating code.
- **`[TRUTHMODE]`**: Zero speculation. All assertions must be backed by diffs or exit codes.
- **`[REDTEAM]`**: Forces reviewer to actively search for race conditions, memory leaks, and security bugs.
- **`[ALT3]`**: Forces implementer to evaluate 3 approaches and pick the minimal optimal solution.
- **`[META]`**: Audits plan feasibility and token budget before execution.
- **`[x10think]` / `[PREDICT]`**: Activates extended deep reasoning compute for hard problems.

### Model & Provider Directives:
- **`[opencode:model]`**: Selects model for OpenCode (e.g. `[opencode:anthropic/claude-opus-4-8]`).
- **`[agy:model]`**: Selects model for Antigravity (e.g. `[agy:Gemini 3.1 Pro (High)]`).
- **`[ks:model]`**: Connects to local KS Server for zero-cost turns (e.g. `[ks:deepseek-reasoner]`).

### Bilingual Substrate:
- If the user writes in **Spanish**, the orchestrator automatically maintains all internal multi-agent reasoning, diffs, and turns in **dense Technical English** (maximizing token efficiency and cross-model fidelity), while presenting the final operator handoff in **Spanish**.

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

Local KS Server (Zero-Cost):
```bash
ask-ks /path/to/project prompt.md output.md
```

## Consensus Workflow

1. Let Claude implement or propose.
2. Let Codex verify.
3. If Codex verifies, stop.
4. If Codex disagrees, let Claude revise or defend once.
5. If disagreement persists, call OpenCode / KS Server as judge.
6. After judge verdict, one agent makes the smallest needed change and the other verifies.
7. If Claude or Codex is unavailable, try OpenCode, Antigravity, and KS Server automatically.
8. A provider that already served as implementer this round is excluded from reviewer fallback selection the same round — it can never review its own implementation. If no distinct supported fallback reviewer is configured after excluding the implementer, the run fails closed (`NO_INDEPENDENT_REVIEWER`) instead of declaring consensus. If primary Codex fails and distinct supported fallback reviewer candidates existed but were unavailable or all failed validation or execution, the run fails closed (`CODEX_ERROR`) instead of declaring consensus.

## Token Budget

- Simple: 1 round.
- Normal: 2 rounds.
- Complex: 3 rounds, OpenCode / KS Server only on disagreement.

The orchestrator only propagates the 5 protocol fields from recent turns. Do not paste logs; reference files in the run artifacts directory.

Final states are `CONSENSUS`, `BLOCKED`, `VERIFY_FAILING`, `CLAUDE_ERROR`, `CODEX_ERROR`, `NO_INDEPENDENT_REVIEWER`, and `MAX_ROUNDS`. `NO_INDEPENDENT_REVIEWER` means no distinct supported fallback reviewer is configured after excluding the implementer. `CODEX_ERROR` covers primary Codex failure when distinct supported fallback reviewer candidates existed but were unavailable or all failed validation or execution. Both paths fail closed and neither emits `CONSENSUS`.
