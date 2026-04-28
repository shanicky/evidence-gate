# Decision Assurance Judge Output Template

Return a single JSON object with this exact top-level shape:

```json
{
  "gate_required": true,
  "gate_reason": "High-stakes production action with incomplete evidence coverage.",
  "candidate_summary": "Claim: disable the worker queue in production.",
  "stakes_tier": "HIGH",
  "requirements": [
    {
      "id": "req-isolation",
      "description": "Show an isolating check that the worker queue is the actual outage driver.",
      "mandatory": true,
      "acceptable_kinds": ["test", "reproduction", "measurement"],
      "status": "missing",
      "evidence_refs": [],
      "notes": "Correlation alone is not sufficient at HIGH stakes."
    }
  ],
  "missing_evidence": [
    "An isolating check showing the queue is the actual outage driver"
  ],
  "conflicting_evidence": [],
  "sufficiency_rule": "PASS requires all mandatory requirements satisfied, no unresolved central conflict, and at least one independent corroborating signal for the central claim at HIGH stakes.",
  "source_independence": {
    "rating": "low",
    "rationale": "All current support comes from the same metrics pipeline."
  },
  "confidence_calibration": {
    "level": "low",
    "rationale": "The evidence supports only an advisory statement, not automatic execution."
  },
  "residual_risk": {
    "description": "Even if the queue is disabled, database pressure may still degrade under peak load.",
    "severity": "medium",
    "mitigations": [
      "Monitor database CPU during the change window"
    ]
  },
  "verdict": "SOFT_PASS",
  "allowed_next_actions": [
    "Present the action as an advisory recommendation"
  ],
  "blocked_next_actions": [
    "Execute the production change automatically"
  ],
  "fallback_behavior": "Downgrade to an advisory recommendation and request targeted corroboration.",
  "suggested_wording": "Current evidence suggests disabling the queue may help, but it still needs independent confirmation before execution.",
  "next_evidence_actions": [
    "Run an isolating canary or controlled reproduction",
    "Validate rollback and blast radius in the target environment"
  ]
}
```

## Rules

- Keep every top-level key present.
- Use `[]` for empty lists.
- Use one of `PASS`, `SOFT_PASS`, `BLOCK`, `CONFLICT`, or `ESCALATE` for
  `verdict`.
- Keep `stakes_tier` present on every invocation.
- Keep `source_independence` and `confidence_calibration` present on every
  invocation as objects with `rating` or `level` plus `rationale`.
- Keep `residual_risk` present on every invocation as an object with
  `description`, `severity`, and `mitigations`.
- `source_independence.rating` uses `high`, `medium`, `low`, or
  `not_applicable`.
- `confidence_calibration.level` uses `high`, `medium`, `low`, or
  `not_applicable`.
- `residual_risk.severity` uses `none`, `low`, `medium`, or `high`.
- Keep `acceptable_kinds` present on every requirement.
- Keep `next_evidence_actions` bounded to the smallest useful set, usually
  `1-3` items.
- If `gate_required` is `false`, use it as a fast exit:
  - set `verdict` to `PASS`
  - set both calibration objects to `not_applicable`
  - set `residual_risk.severity` to `none`
  - keep `residual_risk.mitigations` empty
  - keep `requirements`, `missing_evidence`, and `conflicting_evidence` empty
