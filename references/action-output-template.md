# Decision Assurance Action Output Template

Return a single JSON object with this exact top-level shape:

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

## Rules

- Keep every top-level key present.
- Use one of `allow`, `allow_advisory`, `require_human`, `block`, or
  `escalate` for `governed_action`.
- Keep `audit_record.rule_id` aligned with `action-map.md`.
- Keep `required_followups` explicit and bounded.
- Keep `caller_instructions` directly reusable by the caller.
