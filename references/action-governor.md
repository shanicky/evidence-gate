# Decision Assurance Action Governor

Use this module last in the pipeline.
It maps the judge verdict and the stakes tier to a deterministic runtime action.

## Goal

The governor answers:

**Given this verdict at this tier, what is the strongest action the caller may
now take?**

The governor is not advisory by default.
It applies the fixed mapping in `action-map.md` and returns a structured audit
record.

## Inputs

The governor consumes:

- `stakes_tier` from the Stakes Router
- `verdict` from the Calibrated Judge
- optional `action_policy_override` from the pipeline input
- caller context only when needed to phrase `caller_instructions`

## Output shape

See `action-output-template.md` and `action-schema.json`.

```json
{
  "governed_action": "require_human",
  "audit_record": {
    "rule_id": "SOFT_PASS:HIGH",
    "policy_source": "references/action-map.md",
    "decision_basis": "SOFT_PASS at HIGH stakes allows advisory output but requires human approval before execution.",
    "verdict": "SOFT_PASS",
    "stakes_tier": "HIGH",
    "required_followups": [
      "Obtain explicit human approval before execution"
    ]
  },
  "caller_instructions": "You may present this as advisory, but do not execute it until a human approves the remaining risk."
}
```

## Governed actions

Use exactly these actions:

- `allow`
- `allow_advisory`
- `require_human`
- `block`
- `escalate`

### Meanings

- `allow`: the caller may proceed at the requested strength.
- `allow_advisory`: the caller may continue only with caveats, weaker wording,
  or advisory framing.
- `require_human`: the caller may prepare the recommendation, but a human must
  approve before high-impact execution or settled presentation.
- `block`: do not present or execute the requested claim/action.
- `escalate`: hand off to a human or qualified specialist owner.

## Audit requirements

Every output includes `audit_record`.
Keep it terse but explicit.
It should be sufficient for a caller or log sink to reconstruct why the action
was constrained.

At minimum the audit record must identify:

- the rule that fired
- the verdict
- the tier
- the mapping rationale
- the required follow-ups

## Fast exit

If the router fast-exits and the judge returns `PASS`, the governor still runs
logically and returns:

- `governed_action = allow`
- an audit record showing the fast-exit basis

## No custom remapping

Do not improvise a new mapping during runtime.
If a caller needs a different policy, it should supply a stricter outer policy
layer outside this base skill.

## Strict lookup procedure

Follow these steps in order. Do not skip or reorder.

1. Read `verdict` from the judge output.
2. Read `stakes_tier` from the router output.
3. Find the row matching `verdict` in the inline action map below.
4. Find the column matching `stakes_tier`.
5. Copy the cell value verbatim into `governed_action`.
6. STOP. Do not reconsider, adjust, soften, or elevate `governed_action`
   for any reason — not for execution mode, confidence level, evidence
   quality, domain sensitivity, or any other factor.
7. If `action_policy_override` is present and its `forced_action` is
   stricter, replace `governed_action` with `forced_action`.
8. Write any commentary or reservations into `caller_instructions`, never
   into `governed_action`.

Common error: writing "the map says X, however..." and then using a
different value. This is not allowed. The map cell is final.

## Inline action map

Use this table verbatim. Do not reinterpret, adjust, or override any cell.

| verdict | LOW | MEDIUM | HIGH | CRITICAL |
| --- | --- | --- | --- | --- |
| `PASS` | `allow` | `allow` | `allow` | `allow` |
| `SOFT_PASS` | `allow_advisory` | `allow_advisory` | `require_human` | `require_human` |
| `BLOCK` | `block` | `block` | `block` | `block` |
| `CONFLICT` | `allow_advisory` | `allow_advisory` | `require_human` | `require_human` |
| `ESCALATE` | `escalate` | `escalate` | `escalate` | `escalate` |

Read the verdict row and the tier column. The cell is your `governed_action`.

Frequently confused cells:

- `PASS` at any tier → `allow` (not `allow_advisory`, not `require_human`)
- `PASS` at `CRITICAL` → `allow` (do not re-introduce a human gate after a
  `PASS` verdict)
- `CONFLICT` at `CRITICAL` → `require_human` (not `escalate`)
- `CONFLICT` at `HIGH` → `require_human` (not `block`)

## Optional stricter override

If the caller provides `action_policy_override`, treat it as a reserved
integration hook for stricter governance.

Recommended input shape:

```json
{
  "forced_action": "require_human",
  "rationale": "Production security exceptions always require explicit human approval."
}
```

Rules:

- apply the base mapping from `action-map.md` first
- then keep the stricter of the base action and `forced_action`
- never use the override to loosen the base mapping
- record the override rationale in `caller_instructions` or outer audit logs
