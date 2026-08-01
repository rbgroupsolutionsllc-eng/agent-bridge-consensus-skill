# Agent Bridge V3: Control Plane Contract

## 1. Purpose and Product Boundary

Agent Bridge V3 is a **deterministic local multi-agent control plane** that orchestrates specialized AI providers through structured role-based interactions.

### Core Principles

- **Deterministic**: Rule-based decisions with reproducible outcomes
- **Local**: Operates on local repositories without external dependencies
- **Multi-agent**: Coordinates multiple specialized providers (Claude, Codex, OpenCode, Antigravity/agy)
- **Control plane**: Manages state, transitions, evidence, and human approval gates
- **Provider-neutral**: Decouples roles from specific provider implementations
- **Evidence-driven**: All claims validated through observable artifacts
- **Fail-closed**: Ambiguous states halt execution pending human review
- **Auditable**: Complete event log with cryptographic hashes
- **Resumable**: State persists across interruptions

### Skill vs. Product

The current `agent-bridge-consensus` skill is **one interface** to the V3 runtime, not the entire product. The skill provides a conversational layer; V3 provides the execution engine.

---

## 2. Reference Model and Attribution

### Adopted from Sh3rd3n/megazord

- **Project lifecycle phases**: discuss → plan → execute → verify → review
- **Dependency waves**: Parallel execution within phases, sequential between phases
- **Specialized agents**: Role-specific provider assignments
- **Persistent project state**: Structured state that survives across sessions
- **Acceptance-criteria verification**: Pre-defined success conditions checked before completion

### Adopted from enpixeles-ai/megazord-cli

- **Multiple CLI providers**: Unified interface over different agent implementations
- **Independent proposals and critiques**: Separation of implementation and review
- **Arbitration**: Third-party judgment when primary reviewers disagree
- **Structured work allocation**: Explicit role definitions with capability requirements
- **Execution approval**: Human gates before destructive operations
- **Provider adapters**: Abstraction layer for provider-specific protocols
- **Audit transcripts**: Structured logs of all interactions

### Inspired by Sakana Fugu (Future Scope Only)

- **Adaptive task analysis**: Dynamic role selection based on task characteristics
- **Dynamic team composition**: Runtime provider selection based on capability matching
- **Role and model selection**: Capability-based routing

**Important**: V3A implements a **deterministic policy-based router**, not a learned Fugu-style orchestrator. Learned routing is explicitly deferred to future versions (V4+).

### Designed for Agent Bridge

- **Canonical provider identities**: Normalized aliases (antigravity → agy)
- **Round-scoped role exclusion**: Implementer cannot review own work
- **Protocol validation**: Structured turn format with field-level validation
- **Verification attribution**: Git-based evidence tied to specific providers
- **Fail-closed diagnostics**: Distinction between "no candidate" and "all candidates failed"
- **Installer idempotency**: Byte-exact repeatability across multiple runs
- **Suite-driven development**: 170-case regression suite as contract validation

---

## 3. Non-Goals for V3A

V3A is a **specification and contract block only**. The following are explicitly **out of scope**:

- ❌ Runtime implementation (no V3 execution engine)
- ❌ Dashboard or UI (no visualization layer)
- ❌ IDE integration (no editor plugins)
- ❌ Learned router (no ML-based provider selection)
- ❌ Browser integration (no web automation)
- ❌ Context7 integration (no external knowledge retrieval)
- ❌ Provider API migration (no OAuth flows, no credential management)
- ❌ Changes to current v2 behavior (no modifications to existing orchestrator)
- ❌ Autonomous push or merge (all Git operations require human approval)

V3A defines **what** V3 will be. Subsequent blocks (V3B-V3G) define **how** to build it.

---

## 4. Canonical Provider Identities

### Primary Providers

| Canonical Identity | Display Name | Description |
|-------------------|--------------|-------------|
| `claude` | Claude | Anthropic's Claude (via `bin/ask-claude`) |
| `codex` | Codex | OpenAI's Codex CLI (via `bin/ask-codex`) |
| `opencode` | OpenCode | OpenCode CLI (via `bin/ask-opencode`) |
| `agy` | Antigravity/agy | Antigravity CLI (via `bin/ask-antigravity`) |

### Alias Normalization

```
antigravity → agy
```

All provider comparisons use **canonical identities**. Display names, model names, and CLI names are **never** used for identity checks.

### Rationale

- **Consistency**: Single source of truth for provider identity
- **Security**: Prevents alias confusion attacks
- **Auditing**: Clear event logs with normalized identities
- **Migration**: Stable identity layer even as providers evolve

---

## 5. Canonical Roles

### Role Definitions

#### Planner
- **Purpose**: Decompose goals into actionable plans
- **Permitted actions**: Read files, analyze structure, generate plans
- **Forbidden actions**: Write files, execute commands, modify Git state
- **Workspace writes**: No
- **Git mutation**: No
- **External tools**: No
- **Required evidence**: Plan document with acceptance criteria
- **Valid next roles**: `researcher`, `implementer`

#### Researcher
- **Purpose**: Gather context, explore codebase, retrieve external information
- **Permitted actions**: Read files, execute read-only commands, search documentation
- **Forbidden actions**: Write files, modify Git state, access secrets
- **Workspace writes**: No
- **Git mutation**: No
- **External tools**: Yes (when policy permits)
- **Required evidence**: Research summary with citations
- **Valid next roles**: `implementer`, `reviewer`

#### Implementer
- **Purpose**: Write code, tests, and documentation
- **Permitted actions**: Write files within scope, execute tests, generate artifacts
- **Forbidden actions**: Commit, push, merge, modify files outside scope
- **Workspace writes**: Yes (within authorized scope)
- **Git mutation**: No (commit disabled by default)
- **External tools**: Yes (test frameworks, linters)
- **Required evidence**: Changed files, test results, artifact hashes
- **Valid next roles**: `reviewer`, `verifier`

#### Reviewer
- **Purpose**: Independent validation of implementer claims
- **Permitted actions**: Read files, execute tests, analyze diffs
- **Forbidden actions**: Write source files, modify Git state
- **Workspace writes**: No
- **Git mutation**: No
- **External tools**: Yes (test frameworks, static analyzers)
- **Required evidence**: Review findings with line references
- **Valid next roles**: `verifier`, `judge` (if disagreement)

#### Verifier
- **Purpose**: Execute verification commands, validate acceptance criteria
- **Permitted actions**: Execute allow-listed commands, read outputs
- **Forbidden actions**: Write files, modify Git state
- **Workspace writes**: No
- **Git mutation**: No
- **External tools**: Yes (verification commands only)
- **Required evidence**: Command outputs, exit codes, artifact hashes
- **Valid next roles**: `reviewer` (if verification passes), `judge` (if fails)

#### Judge
- **Purpose**: Arbitrate disagreements between implementer and reviewer
- **Permitted actions**: Read all artifacts, analyze both positions
- **Forbidden actions**: Write files, modify Git state
- **Workspace writes**: No
- **Git mutation**: No
- **External tools**: No
- **Required evidence**: Judgment with reasoning and verdict
- **Valid next roles**: `implementer` (if revision required), `release_manager` (if approved)

#### Release Manager
- **Purpose**: Prepare release, manage Git operations
- **Permitted actions**: Stage files, commit, tag, create PRs (with approval)
- **Forbidden actions**: Merge without approval, delete branches without approval
- **Workspace writes**: Yes (Git metadata only)
- **Git mutation**: Yes (with human approval)
- **External tools**: No
- **Required evidence**: Release notes, changelog, approval records
- **Valid next roles**: None (terminal role)

---

## 6. Provider-Role Capability Matrix

### Capability Definitions

| Capability | Description | Required By |
|------------|-------------|-------------|
| `code_generation` | Can write and modify source code | `implementer` |
| `code_review` | Can analyze code for correctness | `reviewer` |
| `test_execution` | Can run tests and interpret results | `verifier` |
| `arbitration` | Can judge disagreements | `judge` |
| `git_operations` | Can commit, tag, create PRs | `release_manager` |
| `research` | Can search and synthesize information | `researcher` |
| `planning` | Can decompose goals into tasks | `planner` |

### Current Eligibility (V2)

| Provider | Capabilities | Notes |
|----------|--------------|-------|
| `claude` | `code_generation`, `code_review`, `planning`, `research` | Primary implementer |
| `codex` | `code_generation`, `code_review` | Primary reviewer |
| `opencode` | `code_generation`, `code_review`, `test_execution`, `arbitration` | Fallback for both |
| `agy` | `code_generation`, `code_review`, `arbitration` | Judge fallback |

### V3 Runtime Eligibility Factors

Runtime provider selection will consider:

1. **Installation and authentication**: Is the provider CLI installed and authenticated?
2. **Health**: Is the provider responsive?
3. **Rate-limit status**: Has the provider hit quota limits?
4. **Required capability**: Does the provider support the required role capability?
5. **Role exclusion**: Has the provider already been used in a conflicting role this round?
6. **Task policy**: Does the task policy allow this provider for this role?
7. **Operator configuration**: Has the operator explicitly enabled/disabled this provider?
8. **Timeout and failure history**: Has this provider timed out or failed recently?

### Separation of Concerns

**Capability** (what a provider can do) and **eligibility** (whether it should do it now) are distinct concepts. The capability matrix is static; eligibility is dynamic.

---

## 7. Mandatory Independence Rules

### Rule 1: Implementer-Reviewer Separation

The provider that implements code **cannot** review its own work.

```
if (provider == implementer) then (provider != reviewer)
```

### Rule 2: Judge Impartiality

A judge cannot validate its own prior disputed output.

```
if (provider was implementer or reviewer in this round) then (provider != judge)
```

### Rule 3: Identity-Based Independence

Provider identity (canonical form), not role label or display name, determines independence.

```
normalize("antigravity") == "agy"
if (normalize(provider_a) == normalize(provider_b)) then they are NOT independent
```

### Rule 4: Alias Normalization Before Comparison

All provider comparisons use normalized canonical identities.

### Rule 5: Distinction Between Failure and Exclusion

- **Provider failure**: Provider returned error, timeout, or malformed output
- **Role exclusion**: Provider already used in conflicting role this round

These are separate states with different diagnostic messages.

### Rule 6: Fail-Closed on No Independent Reviewer

If no eligible independent reviewer exists, the run **halts** with `NO_INDEPENDENT_REVIEWER`. It does **not** fall back to a self-review.

### Rule 7: No Model Override

No textual claim from a model (e.g., "I am independent") can override these rules. Independence is enforced by the control plane, not by provider self-assessment.

---

## 8. State Machine

### Canonical States

| State | Entry Condition | Allowed Events | Allowed Next States | Required Evidence | Human Approval | Terminal |
|-------|----------------|----------------|---------------------|-------------------|----------------|----------|
| `INIT` | Run created | `RUN_CREATED` | `PRECHECK` | Run metadata | No | No |
| `PRECHECK` | Validating preconditions | `PRECHECK_PASSED`, `PRECHECK_FAILED` | `PLANNING`, `FAILED` | Precheck results | No | No |
| `PLANNING` | Generating plan | `PLAN_CREATED` | `PLAN_REVIEW` | Plan document | No | No |
| `PLAN_REVIEW` | Reviewing plan | `PLAN_REVIEWED` | `AWAITING_EXECUTION_APPROVAL`, `PLANNING` (revise) | Review findings | No | No |
| `AWAITING_EXECUTION_APPROVAL` | Waiting for human approval | `HUMAN_APPROVAL_GRANTED`, `HUMAN_APPROVAL_DENIED` | `IMPLEMENTER_SELECTION`, `CANCELLED` | Approval record | **Yes** | No |
| `IMPLEMENTER_SELECTION` | Selecting implementer | `PROVIDER_SELECTED`, `PROVIDER_SKIPPED` | `IMPLEMENTING`, `FAILED` | Selection log | No | No |
| `IMPLEMENTING` | Implementer writing code | `TURN_STARTED`, `TURN_COMPLETED`, `TURN_REJECTED` | `EVIDENCE_CAPTURE`, `FAILED` | Changed files, test results | No | No |
| `EVIDENCE_CAPTURE` | Capturing artifacts | `EVIDENCE_CAPTURED` | `VERIFYING` | Artifact hashes | No | No |
| `VERIFYING` | Running verification | `VERIFICATION_STARTED`, `VERIFICATION_PASSED`, `VERIFICATION_FAILED` | `REVIEWER_SELECTION`, `IMPLEMENTING` (revise) | Verification outputs | No | No |
| `REVIEWER_SELECTION` | Selecting reviewer | `PROVIDER_SELECTED`, `PROVIDER_SKIPPED` | `REVIEWING`, `FAILED` | Selection log | No | No |
| `REVIEWING` | Reviewer analyzing code | `REVIEW_COMPLETED`, `REVIEW_DISAGREED` | `JUDGING` (if disagreement), `AWAITING_FINAL_APPROVAL` (if approved) | Review findings | No | No |
| `JUDGING` | Judge arbitrating | `JUDGE_SELECTED`, `JUDGMENT_COMPLETED` | `IMPLEMENTING` (revision), `AWAITING_FINAL_APPROVAL` | Judgment reasoning | No | No |
| `AWAITING_FINAL_APPROVAL` | Waiting for final approval | `HUMAN_APPROVAL_GRANTED`, `HUMAN_APPROVAL_DENIED` | `CONSENSUS`, `CANCELLED` | Approval record | **Yes** | No |
| `CONSENSUS` | All approvals received | None | None | Final artifacts | N/A | **Yes** |
| `BLOCKED` | Unresolvable conflict | None | None | Conflict log | N/A | **Yes** |
| `FAILED` | Execution failure | None | None | Failure log | N/A | **Yes** |
| `CANCELLED` | Human cancellation | None | None | Cancellation reason | N/A | **Yes** |

### Forbidden Transitions

- `IMPLEMENTING` → `CONSENSUS` is **forbidden** (must pass through verification and review)
- Terminal states (`CONSENSUS`, `BLOCKED`, `FAILED`, `CANCELLED`) have **no outgoing transitions**

---

## 9. Event Contract

### Append-Only Event Log

All state transitions are recorded as events. Events are immutable once written.

### Event Schema (Core Fields)

```json
{
  "event_id": "uuid",
  "run_id": "uuid",
  "schema_version": "1.0",
  "timestamp": "2026-07-15T00:00:00Z",
  "round": 1,
  "state_before": "IMPLEMENTING",
  "event_type": "TURN_COMPLETED",
  "state_after": "EVIDENCE_CAPTURE",
  "provider": "claude",
  "role": "implementer",
  "evidence_refs": ["evidence-uuid-1", "evidence-uuid-2"],
  "reason": "Turn completed successfully",
  "metadata": {
    "files_changed": 3,
    "tests_passed": 12
  }
}
```

### Canonical Event Types

| Event Type | Description |
|------------|-------------|
| `RUN_CREATED` | New run initialized |
| `PRECHECK_PASSED` | Preconditions validated |
| `PRECHECK_FAILED` | Preconditions failed |
| `PLAN_CREATED` | Plan generated |
| `PLAN_REVIEWED` | Plan reviewed |
| `HUMAN_APPROVAL_GRANTED` | Human approved action |
| `HUMAN_APPROVAL_DENIED` | Human denied action |
| `PROVIDER_SELECTED` | Provider selected for role |
| `PROVIDER_SKIPPED` | Provider skipped (ineligible) |
| `PROVIDER_FAILED` | Provider returned error |
| `TURN_STARTED` | Provider began work |
| `TURN_COMPLETED` | Provider completed work |
| `TURN_REJECTED` | Provider work rejected |
| `EVIDENCE_CAPTURED` | Artifacts captured |
| `VERIFICATION_STARTED` | Verification command started |
| `VERIFICATION_PASSED` | Verification succeeded |
| `VERIFICATION_FAILED` | Verification failed |
| `REVIEW_COMPLETED` | Review completed (approved) |
| `REVIEW_DISAGREED` | Review completed (disagreed) |
| `JUDGE_SELECTED` | Judge selected |
| `JUDGMENT_COMPLETED` | Judgment completed |
| `CONSENSUS_REACHED` | Final consensus achieved |
| `RUN_BLOCKED` | Run blocked (unresolvable) |
| `RUN_FAILED` | Run failed (error) |
| `RUN_CANCELLED` | Run cancelled (human) |

### Field Nullability

- `provider` and `role`: May be null for `RUN_CREATED`, `HUMAN_APPROVAL_*`
- `evidence_refs`: May be empty array `[]`
- `reason`: Required (never null)
- `metadata`: May be empty object `{}`

---

## 10. Git Evidence Contract

### Evidence Types

| Evidence Type | Description |
|---------------|-------------|
| `baseline_head` | HEAD before implementation |
| `final_head` | HEAD after implementation |
| `staged_files` | Files staged for commit |
| `unstaged_files` | Modified but unstaged files |
| `untracked_files` | New files not yet tracked |
| `changed_file_paths` | List of all changed files |
| `allowed_scope_paths` | Files within authorized scope |
| `scope_violations` | Files outside authorized scope |
| `diff_hash` | SHA-256 of unified diff |
| `diff_check` | Output of `git diff --check` |
| `commands_executed` | List of executed commands |
| `exit_codes` | Exit codes for each command |
| `stdout_hashes` | SHA-256 of stdout for each command |
| `stderr_hashes` | SHA-256 of stderr for each command |
| `verification_jobs` | Verification command results |
| `repository_clean` | Boolean: working tree clean? |
| `before_snapshot` | Pre-implementation state hash |
| `after_snapshot` | Post-implementation state hash |
| `evidence_generated_at` | Timestamp of evidence capture |

### Claim vs. Observation

| Category | Description |
|----------|-------------|
| `model_declared_changes` | Files the provider claims to have changed |
| `observed_changes` | Files actually changed (per Git) |
| `undeclared_observed_changes` | Changed files not declared by provider |
| `declared_but_unobserved_changes` | Declared files with no observed changes |

### Authority

- **Model claims are informational** (provider self-reports)
- **Git and command results are authoritative** (observable evidence)

Discrepancies between claims and observations trigger review.

---

## 11. Permission Model

### Initial Technical Policy

| Role | Read Files | Write Files | Execute Commands | Git Mutation | External Tools |
|------|-----------|-------------|------------------|--------------|----------------|
| Planner | Yes | No | No | No | No |
| Researcher | Yes | No | Read-only | No | Yes (policy-gated) |
| Implementer | Yes | Yes (scoped) | Yes (tests) | No | Yes (test/lint) |
| Reviewer | Yes | No | Yes (tests) | No | Yes (test/lint) |
| Verifier | Yes | No | Yes (allow-listed) | No | Yes (verification) |
| Judge | Yes | No | No | No | No |
| Release Manager | Yes | Yes (Git metadata) | No | Yes (with approval) | No |

### Git Operations

| Operation | Default Permission | Override |
|-----------|-------------------|----------|
| `git add` | Release Manager only | Human approval |
| `git commit` | Release Manager only | Human approval |
| `git push` | Release Manager only | Human approval |
| `git merge` | Release Manager only | Human approval |
| `git tag` | Release Manager only | Human approval |
| Branch deletion | Forbidden | Human approval |

---

## 12. Deterministic Selection Policy v1

### Algorithm

```python
def select_provider(role, required_capabilities, round_state, policy):
    # 1. Filter unsupported providers
    candidates = [p for p in policy.enabled_providers if p.is_supported()]
    
    # 2. Normalize aliases
    candidates = [normalize(p) for p in candidates]
    
    # 3. Remove failed providers
    candidates = [p for p in candidates if p not in round_state.failed_providers]
    
    # 4. Filter by required capabilities
    candidates = [p for p in candidates if p.has_capabilities(required_capabilities)]
    
    # 5. Enforce role independence
    candidates = [p for p in candidates if p not in round_state.excluded_providers]
    
    # 6. Apply configured provider preference
    candidates = sort_by_preference(candidates, policy.provider_preference)
    
    # 7. Deterministic tie-breaking
    if len(candidates) > 1:
        candidates = sort_by_deterministic_key(candidates, round_state.run_id)
    
    # 8. Record selection decision
    log_selection(candidates, round_state)
    
    # 9. Fail closed if no eligible provider
    if len(candidates) == 0:
        raise NoEligibleProviderError(role, required_capabilities)
    
    return candidates[0]
```

### Deterministic Tie-Breaking

When multiple providers are equally eligible, use:

```python
def sort_by_deterministic_key(providers, run_id):
    # Stable sort by (provider_canonical_name, role, run_id_hash)
    key = hashlib.sha256(f"{run_id}:{role}".encode()).hexdigest()
    return sorted(providers, key=lambda p: (p.canonical_name, key))
```

### Selection Logging

Every selection decision records:

- Which providers were considered
- Why each was included or excluded
- Which provider was selected and why
- Timestamp and round context

---

## 13. Human Approval Gates

### Required Approvals

| Action | Approval Required | Default |
|--------|------------------|---------|
| Workspace mutation begins | Yes | Require explicit approval |
| Commit | Yes | Require explicit approval |
| Push | Yes | Require explicit approval |
| Opening non-draft PR | Yes | Require explicit approval |
| Marking PR ready | Yes | Require explicit approval |
| Merge | Yes | Require explicit approval |
| Branch deletion | Yes | Require explicit approval |
| Release tagging | Yes | Require explicit approval |
| Accessing unauthorized secrets | Yes | Require explicit approval |

### Approval Record

Each approval is recorded as an event with:

- Approver identity (human operator)
- Timestamp
- Action approved
- Context (run_id, round, state)
- Approval reason (optional)

---

## 14. Compatibility and Migration

### V2 Compatibility

- Existing `bin/agent-turns` remains **fully operational** during V3 development
- V3 components initially **wrap** rather than replace v2
- v2 output may be **translated** into V3 events (adapter layer)
- No V3 state is treated as authoritative until the V3 engine exists

### Rollback Strategy

Rollback means:

1. Disable the V3 wrapper
2. Return to current v2 CLI
3. No data loss (V3 events are additive, not destructive)

### Artifact Isolation

- V3 artifacts (schemas, contracts, logs) are stored in `docs/v3/` and `schemas/v3/`
- V3 artifacts **do not** silently alter v2 execution
- V3 event logs are append-only and do not modify v2 state

---

## 15. Failure Model

### Failure Categories

| Category | Examples | Behavior |
|----------|----------|----------|
| Provider unavailable | CLI not installed, authentication failed | Skip provider, try next |
| Rate limit | Provider quota exceeded | Skip provider, retry after backoff |
| Timeout | Provider did not respond in time | Mark failed, try next |
| Nonzero exit | Command returned error | Mark failed, log exit code |
| Empty output | Provider returned no output | Mark failed, log error |
| Malformed protocol | Output does not match schema | Mark failed, log validation error |
| No independent reviewer | All eligible providers excluded | Halt with `NO_INDEPENDENT_REVIEWER` |
| Verification failure | Acceptance criteria not met | Return to implementer for revision |
| Scope violation | Files changed outside authorized scope | Halt with `SCOPE_VIOLATION` |
| Stale evidence | Evidence older than threshold | Re-capture or halt |
| Corrupt state | State file malformed | Halt with `CORRUPT_STATE` |
| Duplicate run | Run ID already exists | Halt with `DUPLICATE_RUN` |
| Interrupted run | Process killed mid-execution | Resume from last checkpoint |
| Unknown transition | State machine violation | Halt with `UNKNOWN_TRANSITION` |
| Human rejection | Human denied approval | Halt with `HUMAN_REJECTION` |

### Fail-Closed Principle

All **unknown or ambiguous conditions** halt execution and require human review. The system never guesses.

---

## 16. V3 Phase Boundaries

| Phase | Scope | Deliverables |
|-------|-------|--------------|
| **V3A** | Contracts and schemas | Control plane contract, JSON schemas, contract tests |
| **V3B** | Evidence engine | Git evidence capture, artifact hashing, claim-vs-observation |
| **V3C** | Deterministic state engine | State machine, transition validation, event log |
| **V3D** | Provider-role orchestration | Capability matching, selection policy, independence enforcement |
| **V3E** | Structured verification jobs | Verification command registry, allow-lists, result capture |
| **V3F** | External tool adapters | Provider adapters, protocol translation, error handling |
| **V3G** | Integration and 3.0 release | End-to-end testing, documentation, migration guide |
| **V4** | Dashboard and desktop interface | Visualization layer, IDE integration, user experience |

### Current Phase: V3A

This document and accompanying schemas define the V3A contract. No implementation is included.

---

## Summary

Agent Bridge V3 is a deterministic local multi-agent control plane that orchestrates specialized providers through structured role-based interactions. V3A defines the contracts and schemas; subsequent phases implement the runtime.

Key principles:

- **Deterministic**: Rule-based, reproducible
- **Provider-neutral**: Roles decoupled from providers
- **Evidence-driven**: Claims validated through artifacts
- **Fail-closed**: Ambiguity halts execution
- **Auditable**: Complete event log
- **Resumable**: State persists across interruptions

V3A is specification only. No runtime code is included.
