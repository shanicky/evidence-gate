# Decision Assurance Pipeline Output Template

Return a single JSON object with this exact top-level shape:

```json
{
  "stakes": {
    "stakes_tier": "HIGH",
    "routing_decision": "assure",
    "tier_rationale": "Production-impacting action with hard reversibility and possible service disruption.",
    "routing_signals": [
      "execution_mode=auto",
      "impact_profile.scope=production",
      "impact_profile.reversibility=hard",
      "impact_profile.blast_radius=single_service"
    ]
  },
  "judgment": {
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
  },
  "action": {
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
}
```

## Rules

- Keep all three top-level objects present.
- Keep `stakes.stakes_tier` and `judgment.stakes_tier` aligned.
- Preserve the judge fast-exit shape when `routing_decision = fast_exit`.
- For fast exit, use `judgment.source_independence.rating = not_applicable` and
  `judgment.confidence_calibration.level = not_applicable`.
- For fast exit, set `judgment.residual_risk.severity = none` and keep
  `judgment.residual_risk.mitigations` empty.
- Keep `action.governed_action` aligned with `action-map.md`.
