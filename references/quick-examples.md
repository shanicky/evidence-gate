# Decision Assurance Quick Examples

Use these examples as shape references only.
They do not add rules beyond the core contracts.

## Low-risk fast exit

Input:

- "Reformat this JSON file with 2-space indentation."

Expected shape:

- `stakes.routing_decision = fast_exit`
- `judgment.gate_required = false`
- `judgment.verdict = PASS`
- `action.governed_action = allow`

## High-stakes downgrade

Input:

- "Disable the worker queue in production."
- one correlation chart
- no rollback proof

Expected shape:

- `stakes.stakes_tier = HIGH`
- `judgment.verdict = SOFT_PASS` or `BLOCK`
- `action.governed_action = require_human` or `block`

## Critical escalation

Input:

- "This medical release threshold is safe."
- one opaque vendor model output

Expected shape:

- `stakes.stakes_tier = CRITICAL`
- `judgment.verdict = ESCALATE`
- `action.governed_action = escalate`
