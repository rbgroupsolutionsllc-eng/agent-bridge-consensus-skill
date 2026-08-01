#!/usr/bin/env bash
set -euo pipefail

# Test V3A control plane contracts
# Validates that all schema files and contract documentation meet requirements

echo "=== V3A Contract Validation Tests ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONTRACT_DOC="$REPO_ROOT/docs/v3/control-plane-contract.md"
RUN_STATE_SCHEMA="$REPO_ROOT/schemas/v3/run-state.schema.json"
EVENT_SCHEMA="$REPO_ROOT/schemas/v3/event.schema.json"
EVIDENCE_SCHEMA="$REPO_ROOT/schemas/v3/evidence.schema.json"

TESTS_PASSED=0
TESTS_FAILED=0

pass_test() {
    echo "✓ $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    echo "✗ $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 1: Schema files exist
echo "Test 1: Schema files exist"
if [[ -f "$RUN_STATE_SCHEMA" ]]; then
    pass_test "run-state.schema.json exists"
else
    fail_test "run-state.schema.json missing"
fi

if [[ -f "$EVENT_SCHEMA" ]]; then
    pass_test "event.schema.json exists"
else
    fail_test "event.schema.json missing"
fi

if [[ -f "$EVIDENCE_SCHEMA" ]]; then
    pass_test "evidence.schema.json exists"
else
    fail_test "evidence.schema.json missing"
fi

if [[ -f "$CONTRACT_DOC" ]]; then
    pass_test "control-plane-contract.md exists"
else
    fail_test "control-plane-contract.md missing"
fi

# Test 2: Schemas parse as valid JSON
echo ""
echo "Test 2: Schemas parse as valid JSON"
if python3 -c "import json; json.load(open('$RUN_STATE_SCHEMA'))" 2>/dev/null; then
    pass_test "run-state.schema.json is valid JSON"
else
    fail_test "run-state.schema.json is invalid JSON"
fi

if python3 -c "import json; json.load(open('$EVENT_SCHEMA'))" 2>/dev/null; then
    pass_test "event.schema.json is valid JSON"
else
    fail_test "event.schema.json is invalid JSON"
fi

if python3 -c "import json; json.load(open('$EVIDENCE_SCHEMA'))" 2>/dev/null; then
    pass_test "evidence.schema.json is valid JSON"
else
    fail_test "evidence.schema.json is invalid JSON"
fi

# Test 3: $schema is Draft 2020-12
echo ""
echo "Test 3: Schemas declare Draft 2020-12"
if python3 -c "import json; s=json.load(open('$RUN_STATE_SCHEMA')); assert s.get('\$schema') == 'https://json-schema.org/draft/2020-12/schema'" 2>/dev/null; then
    pass_test "run-state.schema.json declares Draft 2020-12"
else
    fail_test "run-state.schema.json does not declare Draft 2020-12"
fi

if python3 -c "import json; s=json.load(open('$EVENT_SCHEMA')); assert s.get('\$schema') == 'https://json-schema.org/draft/2020-12/schema'" 2>/dev/null; then
    pass_test "event.schema.json declares Draft 2020-12"
else
    fail_test "event.schema.json does not declare Draft 2020-12"
fi

if python3 -c "import json; s=json.load(open('$EVIDENCE_SCHEMA')); assert s.get('\$schema') == 'https://json-schema.org/draft/2020-12/schema'" 2>/dev/null; then
    pass_test "evidence.schema.json declares Draft 2020-12"
else
    fail_test "evidence.schema.json does not declare Draft 2020-12"
fi

# Test 4: $id values are present and unique
echo ""
echo "Test 4: Schemas have unique \$id values"
IDS=$(python3 <<'PYEOF'
import json
ids = []
for schema_file in ["schemas/v3/run-state.schema.json", "schemas/v3/event.schema.json", "schemas/v3/evidence.schema.json"]:
    try:
        with open(schema_file) as f:
            s = json.load(f)
            if '$id' in s:
                ids.append(s['$id'])
    except:
        pass
print('\n'.join(ids))
PYEOF
)

ID_COUNT=$(echo "$IDS" | wc -l)
UNIQUE_COUNT=$(echo "$IDS" | sort -u | wc -l)

if [[ "$ID_COUNT" -eq 3 && "$UNIQUE_COUNT" -eq 3 ]]; then
    pass_test "All schemas have unique \$id values"
else
    fail_test "Schemas do not have 3 unique \$id values (found $ID_COUNT total, $UNIQUE_COUNT unique)"
fi

# Test 5: Required top-level fields are present
echo ""
echo "Test 5: Required fields present in schemas"
python3 <<'PYEOF'
import json
import sys

try:
    with open("schemas/v3/run-state.schema.json") as f:
        run_state = json.load(f)
    
    required_fields = [
        "schema_version", "run_id", "state", "round", "goal", "workspace",
        "baseline", "provider_assignments", "failed_providers", "excluded_providers",
        "evidence_refs", "pending_approval", "last_event_id", "created_at",
        "updated_at", "terminal_result"
    ]
    
    if all(f in run_state.get("properties", {}) for f in required_fields):
        print("✓ run-state.schema.json has all required fields")
        sys.exit(0)
    else:
        print("✗ run-state.schema.json missing required fields")
        sys.exit(1)
except Exception as e:
    print(f"✗ Error validating run-state.schema.json: {e}")
    sys.exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

python3 <<'PYEOF'
import json
import sys

try:
    with open("schemas/v3/event.schema.json") as f:
        event = json.load(f)
    
    required_fields = [
        "event_id", "run_id", "schema_version", "timestamp", "round",
        "state_before", "event_type", "state_after", "reason"
    ]
    
    if all(f in event.get("properties", {}) for f in required_fields):
        print("✓ event.schema.json has all required fields")
        sys.exit(0)
    else:
        print("✗ event.schema.json missing required fields")
        sys.exit(1)
except Exception as e:
    print(f"✗ Error validating event.schema.json: {e}")
    sys.exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Canonical provider enums match across schemas
echo ""
echo "Test 6: Canonical provider enums consistent"
python3 <<'PYEOF'
import json

providers = set()
for schema_file in ["schemas/v3/run-state.schema.json", "schemas/v3/event.schema.json", "schemas/v3/evidence.schema.json"]:
    with open(schema_file) as f:
        s = json.load(f)
    
    # Check in properties
    for prop_name, prop_def in s.get("properties", {}).items():
        if "enum" in prop_def and isinstance(prop_def["enum"], list):
            if all(p in ["claude", "codex", "opencode", "agy", None] for p in prop_def["enum"] if p is not None):
                providers.update(p for p in prop_def["enum"] if p is not None)
    
    # Check in $defs
    for def_name, def_def in s.get("$defs", {}).items():
        if "enum" in def_def:
            if all(p in ["claude", "codex", "opencode", "agy"] for p in def_def["enum"]):
                providers.update(def_def["enum"])

expected = {"claude", "codex", "opencode", "agy"}
if providers == expected:
    print("✓ Canonical provider enums match: claude, codex, opencode, agy")
    exit(0)
else:
    print(f"✗ Provider enums mismatch: expected {expected}, got {providers}")
    exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Canonical role enums match across schemas
echo ""
echo "Test 7: Canonical role enums consistent"
python3 <<'PYEOF'
import json

roles = set()
for schema_file in ["schemas/v3/event.schema.json", "schemas/v3/evidence.schema.json"]:
    with open(schema_file) as f:
        s = json.load(f)
    
    # Check in $defs
    if "canonical_role" in s.get("$defs", {}):
        role_def = s["$defs"]["canonical_role"]
        if "enum" in role_def:
            roles.update(role_def["enum"])

expected = {"planner", "researcher", "implementer", "reviewer", "verifier", "judge", "release_manager"}
if roles == expected:
    print("✓ Canonical role enums match")
    exit(0)
else:
    print(f"✗ Role enums mismatch: expected {expected}, got {roles}")
    exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: State enums match between contract and run-state schema
echo ""
echo "Test 8: State enums synchronized"
python3 <<'PYEOF'
import json
import re

# Extract states from schema
with open("schemas/v3/run-state.schema.json") as f:
    schema = json.load(f)

schema_states = set()
for prop_name, prop_def in schema.get("properties", {}).items():
    if "enum" in prop_def:
        schema_states.update(prop_def["enum"])

# Extract states from contract document (section 8 only)
with open("docs/v3/control-plane-contract.md") as f:
    content = f.read()

# Extract section 8 content
section_8_match = re.search(r'## 8\. State Machine.*?^## 9\.', content, re.DOTALL | re.MULTILINE)
if section_8_match:
    section_8 = section_8_match.group(0)
    # Extract state names from first column of state table
    state_pattern = r'^\| `([A-Z_]+)` \|'
    contract_states = set(re.findall(state_pattern, section_8, re.MULTILINE))
else:
    contract_states = set()

if schema_states == contract_states:
    print(f"✓ State enums match ({len(schema_states)} states)")
    exit(0)
else:
    print(f"✗ State enums mismatch")
    print(f"  Schema only: {schema_states - contract_states}")
    print(f"  Contract only: {contract_states - schema_states}")
    exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 9: Event enums match between contract and event schema
echo ""
echo "Test 9: Event enums synchronized"
python3 <<'PYEOF'
import json
import re

# Extract events from schema
with open("schemas/v3/event.schema.json") as f:
    schema = json.load(f)

event_type_def = schema["properties"]["event_type"]
schema_events = set(event_type_def.get("enum", []))

# Extract events from contract document (section 9 only)
with open("docs/v3/control-plane-contract.md") as f:
    content = f.read()

# Extract section 9 content
section_9_match = re.search(r'## 9\. Event Contract.*?^## 10\.', content, re.DOTALL | re.MULTILINE)
if section_9_match:
    section_9 = section_9_match.group(0)
    # Extract event names from event table
    event_pattern = r'^\| `([A-Z_]+)` \|'
    contract_events = set(re.findall(event_pattern, section_9, re.MULTILINE))
else:
    contract_events = set()

# Events are already filtered by section 9

if schema_events == contract_events:
    print(f"✓ Event enums match ({len(schema_events)} events)")
    exit(0)
else:
    print(f"✗ Event enums mismatch")
    print(f"  Schema only: {schema_events - contract_events}")
    print(f"  Contract only: {contract_events - schema_events}")
    exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 10-12: Transition validation
echo ""
echo "Test 10-12: State machine transitions valid"
python3 <<'PYEOF'
import json

with open("schemas/v3/run-state.schema.json") as f:
    schema = json.load(f)

states = set(schema["properties"]["state"]["enum"])

# Extract transitions from contract (section 8 state machine table)
with open("docs/v3/control-plane-contract.md") as f:
    content = f.read()

import re
# Extract section 8 content
section_8_match = re.search(r'## 8\. State Machine.*?^## 9\.', content, re.DOTALL | re.MULTILINE)
if section_8_match:
    section_8 = section_8_match.group(0)
    # Find transition table rows (state in first column, allowed next states in fourth column)
    # Pattern: | `STATE` | ... | ... | `NEXT1`, `NEXT2` | ...
    transition_pattern = r'^\| `([A-Z_]+)` \|[^|]*\|[^|]*\| `([^`]+)` \|'
    matches = re.findall(transition_pattern, section_8, re.MULTILINE)
    
    transitions = []
    for source, dest_str in matches:
        # Parse multiple destinations (e.g., "PLANNING, FAILED")
        dests = [d.strip() for d in dest_str.split(',')]
        for dest in dests:
            if dest and dest != 'None':
                transitions.append((source, dest))
else:
    transitions = []

# Test 10: All transition sources and destinations are declared states
invalid_states = set()
for source, dest in transitions:
    if source not in states:
        invalid_states.add(source)
    if dest not in states:
        invalid_states.add(dest)

if not invalid_states:
    print("✓ Test 10: All transition sources and destinations are declared states")
else:
    print(f"✗ Test 10: Invalid states in transitions: {invalid_states}")
    exit(1)

# Test 11: Terminal states have no outgoing transitions
terminal_states = {"CONSENSUS", "BLOCKED", "FAILED", "CANCELLED"}
outgoing_from_terminal = [(s, d) for s, d in transitions if s in terminal_states]

if not outgoing_from_terminal:
    print("✓ Test 11: Terminal states have no outgoing transitions")
else:
    print(f"✗ Test 11: Terminal states have outgoing transitions: {outgoing_from_terminal}")
    exit(1)

# Test 12: IMPLEMENTING cannot transition directly to CONSENSUS
implementing_to_consensus = [t for t in transitions if t[0] == "IMPLEMENTING" and t[1] == "CONSENSUS"]

if not implementing_to_consensus:
    print("✓ Test 12: IMPLEMENTING cannot transition directly to CONSENSUS")
else:
    print("✗ Test 12: IMPLEMENTING can transition directly to CONSENSUS (forbidden)")
    exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 3))
else
    TESTS_FAILED=$((TESTS_FAILED + 3))
fi

# Test 13: Implementer/reviewer independence rule present
echo ""
echo "Test 13: Implementer/reviewer independence rule present"
if grep -q "Implementer-Reviewer Separation\|implementer.*reviewer.*independent\|independent reviewer" "$CONTRACT_DOC"; then
    pass_test "Implementer/reviewer independence rule documented"
else
    fail_test "Implementer/reviewer independence rule not found"
fi

# Test 14: Deterministic, rule-based router boundary present
echo ""
echo "Test 14: Deterministic router boundary present"
if grep -q "Deterministic Selection Policy\|rule-based\|deterministic.*router" "$CONTRACT_DOC"; then
    pass_test "Deterministic router boundary documented"
else
    fail_test "Deterministic router boundary not found"
fi

# Test 15: Sakana Fugu not described as incremental methodology
echo ""
echo "Test 15: Sakana Fugu reference accurate"
if grep -qi "Sakana Fugu.*inspiration\|Sakana Fugu.*future scope" "$CONTRACT_DOC"; then
    if ! grep -qi "Sakana Fugu.*incremental\|Fugu.*methodology" "$CONTRACT_DOC"; then
        pass_test "Sakana Fugu correctly described as inspiration, not incremental methodology"
    else
        fail_test "Sakana Fugu incorrectly described as incremental methodology"
    fi
else
    fail_test "Sakana Fugu reference not found or inaccurate"
fi

# Test 16: Two distinct Megazord references identified separately
echo ""
echo "Test 16: Megazord references separated"
if grep -q "Sh3rd3n/megazord" "$CONTRACT_DOC" && grep -q "enpixeles-ai/megazord-cli" "$CONTRACT_DOC"; then
    pass_test "Two distinct Megazord references identified separately"
else
    fail_test "Megazord references not properly separated"
fi

# Test 17: V2 compatibility documented
echo ""
echo "Test 17: V2 compatibility and rollback documented"
if grep -q "V2 Compatibility\|v2.*operational\|existing.*agent-turns" "$CONTRACT_DOC"; then
    pass_test "V2 compatibility documented"
else
    fail_test "V2 compatibility not documented"
fi

if grep -q "Rollback\|rollback.*strategy\|disable.*V3" "$CONTRACT_DOC"; then
    pass_test "Rollback strategy documented"
else
    fail_test "Rollback strategy not documented"
fi

# Test 18: Dashboard marked out of scope for V3A
echo ""
echo "Test 18: Dashboard out of scope for V3A"
if grep -q "dashboard\|UI\|visualization" "$CONTRACT_DOC"; then
    if grep -q "out of scope\|non-goal\|deferred" "$CONTRACT_DOC"; then
        pass_test "Dashboard marked as out of scope"
    else
        fail_test "Dashboard mentioned but not marked out of scope"
    fi
else
    fail_test "Dashboard not mentioned in non-goals"
fi

# Test 19: Only authorized files changed
echo ""
echo "Test 19: Only authorized files created"
cd "$REPO_ROOT"

# Get all untracked files (new files only)
CHANGED_FILES=$(git ls-files --others --exclude-standard | sort)

EXPECTED_FILES="docs/v3/control-plane-contract.md
schemas/v3/event.schema.json
schemas/v3/evidence.schema.json
schemas/v3/run-state.schema.json
tests/test-v3a-contracts.sh"

if [[ "$CHANGED_FILES" == "$EXPECTED_FILES" ]]; then
    pass_test "Only authorized files created"
else
    fail_test "Unexpected files created or missing expected files"
    echo "  Expected:"
    echo "$EXPECTED_FILES" | sed 's/^/    /'
    echo "  Got:"
    echo "$CHANGED_FILES" | sed 's/^/    /'
fi

# Summary
echo ""
echo "=== Test Summary ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
