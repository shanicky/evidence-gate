# Decision Assurance Pipeline Input Template

When a caller wants explicit control over the whole pipeline, use this JSON
shape:

```json
{
  "claim": "Disable the worker queue in production.",
  "claim_type": "action",
  "domain": "sre",
  "execution_mode": "auto",
  "target_strength": "execute",
  "impact_profile": {
    "scope": "production",
    "reversibility": "hard",
    "blast_radius": "single_service",
    "time_sensitivity": "urgent",
    "affected_assets": ["worker-queue", "order-pipeline"]
  },
  "stakes_override": "HIGH",
  "known_evidence": [
    {
      "id": "ev-1",
      "summary": "A canary test shows the outage disappears when the queue is disabled.",
      "kind": "test",
      "source": "production canary",
      "artifact_ref": "runbooks/canary-queue-disable.md",
      "reliability": "high",
      "timestamp": "2026-03-18T09:15:00Z",
      "environment": "production",
      "freshness": "current",
      "independence_group": "canary-control-plane",
      "supports": ["req-isolation"],
      "contradicts": []
    }
  ],
  "alternatives_checked": [
    "The database is the primary outage source instead of the queue."
  ],
  "available_tools": ["logs", "canary", "rollback_runbook"],
  "policy_overrides": [],
  "action_policy_override": {
    "forced_action": "require_human",
    "rationale": "Production mitigations still require explicit human approval under local policy."
  }
}
```

## Rules

- `claim` is the only required field for a minimal invocation.
- `impact_profile.scope` should describe where harm would land:
  `local`, `team`, `service`, `production`, or `external`.
- `impact_profile.reversibility` should describe recovery difficulty:
  `easy`, `moderate`, `hard`, or `irreversible`.
- `impact_profile.blast_radius` may be `isolated`, `single_service`,
  `multi_service`, or `org_wide`.
- `impact_profile.time_sensitivity` may be `none`, `low`, `urgent`, or
  `immediate`.
- `impact_profile.affected_assets` should list named assets when the caller
  knows them.
- Legacy callers may still send top-level `impact_scope` and `reversibility` as
  flat aliases. When both alias fields and `impact_profile` are present, use
  `impact_profile` as the source of truth.
- `stakes_override` is optional. Use it when an outer workflow has already
  classified the case and wants to pin or raise the tier. Do not use it to
  lower stakes below the router's best assessment.
- `action_policy_override` is optional. It should only tighten the final
  `governed_action`, never loosen the base action map.
- Keep `known_evidence` explicit and artifact-linked.
- Provenance fields such as `timestamp`, `environment`, `freshness`, and
  `independence_group` are optional, but strongly preferred for consequential
  cases.
- Keep `policy_overrides` concise and operational.
