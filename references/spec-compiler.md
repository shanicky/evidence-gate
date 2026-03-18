# Decision Assurance Spec Compiler

Use this protocol for an external compiler that converts organization-specific
policy packs into the existing `decision-assurance` pipeline input fields.

The Spec Compiler is not part of the base skill runtime.
It is an outer tool that prepares stricter input before the base skill runs.

## Goal

The compiler answers one question:

**How can an organization tighten stakes routing, requirement injection, action
governance, and tool skepticism without editing the base skill?**

It does this by compiling a policy pack into:

- `stakes_override`
- `policy_overrides`
- `action_policy_override`

The base skill remains unchanged.

## Non-goals

The Spec Compiler does not:

- replace the base skill's single-pass runtime
- add hidden state to the base skill
- loosen the base action map
- lower a stakes tier below what the base skill would infer

## Policy pack shape

Validate policy packs with `spec-compiler-schema.json`.

Canonical YAML shape:

```yaml
policy_pack:
  id: "sre-prod-v1"
  version: "1.0.0"
  domain: "sre"
  description: "Production SRE assurance policy"

  tier_overrides:
    - match:
        impact_profile.scope: "production"
        execution_mode: "auto"
      minimum_tier: "HIGH"

  requirement_library:
    - id: "req-rollback"
      description: "Verified rollback path exists"
      mandatory: true
      acceptable_kinds: ["test", "reproduction", "policy"]
      applies_when:
        claim_type: "action"
        impact_profile.reversibility: ["hard", "irreversible"]

  action_map_overrides:
    - match:
        verdict: "SOFT_PASS"
        stakes_tier: "MEDIUM"
      override_action: "require_human"
      rationale: "Org policy: all production-adjacent SOFT_PASS needs human sign-off"

  tool_skepticism_overrides:
    - tool_type: "observational_query"
      override_skepticism: "high"
      rationale: "Dashboard data in this org has known staleness issues"
```

## Match language

`match` and `applies_when` blocks use flat dotted-path keys that refer to the
existing pipeline input and output fields.

Typical keys:

- `claim_type`
- `domain`
- `execution_mode`
- `target_strength`
- `impact_profile.scope`
- `impact_profile.reversibility`
- `impact_profile.blast_radius`
- `impact_profile.time_sensitivity`
- `stakes_tier`
- `verdict`

Supported value forms:

- a single scalar string
- an array of strings meaning "match any of these"

If a key is missing in the runtime input, the match fails unless the caller has
already normalized that field.

## Compilation stages

Compile policy packs in this order:

1. Normalize the incoming pipeline input.
2. Apply `tier_overrides`.
3. Inject `requirement_library` entries into `policy_overrides`.
4. Apply `action_map_overrides`.
5. Emit `tool_skepticism_overrides` into `policy_overrides`.
6. Return compiled pipeline input deltas.

## Tier overrides

Each tier override has:

- `match`
- `minimum_tier`

Semantics:

- evaluate all matching rules
- keep the highest matching `minimum_tier`
- never use a compiler rule to lower the tier

If no rule matches, emit no `stakes_override`.

## Requirement library

Each requirement entry has:

- `id`
- `description`
- `mandatory`
- `acceptable_kinds`
- `applies_when`

Compilation result:

- emit a `policy_overrides` entry of type `requirement_injection`
- keep the original requirement fields intact
- add compiler metadata so downstream tooling can trace the source pack

Compiled override example:

```json
{
  "type": "requirement_injection",
  "source_policy_pack": "sre-prod-v1",
  "requirement": {
    "id": "req-rollback",
    "description": "Verified rollback path exists",
    "mandatory": true,
    "acceptable_kinds": ["test", "reproduction", "policy"]
  }
}
```

The base skill continues to decide how to phrase or evaluate the injected
requirement.
The compiler only ensures the requirement is present in the caller-supplied
policy layer.

## Action map overrides

Each override has:

- `match`
- `override_action`
- `rationale`

Semantics:

- evaluate overrides against the current `(verdict, stakes_tier)` pair
- only allow stricter outcomes than the base action map
- if multiple overrides match, keep the strictest action

Recommended strictness ordering:

- `allow`
- `allow_advisory`
- `require_human`
- `block`
- `escalate`

If two actions are incomparable in local policy, prefer the one that increases
human control over autonomous continuation.

Compiled output example:

```json
{
  "action_policy_override": {
    "forced_action": "require_human",
    "rationale": "Org policy: all production-adjacent SOFT_PASS needs human sign-off"
  }
}
```

## Tool skepticism overrides

Each override has:

- `tool_type`
- `override_skepticism`
- `rationale`

Supported tool types:

- `deterministic_check`
- `controlled_test`
- `observational_query`
- `search_retrieval`
- `model_inference`
- `human_report`

Semantics:

- only raise skepticism, never lower it
- if multiple overrides exist for the same tool type, keep the highest
  skepticism
- emit the override into `policy_overrides` so the caller can pass it to the
  base skill without adding a new top-level field

Compiled override example:

```json
{
  "type": "tool_skepticism_override",
  "source_policy_pack": "sre-prod-v1",
  "tool_type": "observational_query",
  "override_skepticism": "high",
  "rationale": "Dashboard data in this org has known staleness issues"
}
```

## Compiled output shape

The compiler emits a JSON fragment that can be merged into the existing
pipeline input:

```json
{
  "stakes_override": "HIGH",
  "policy_overrides": [
    {
      "type": "requirement_injection",
      "source_policy_pack": "sre-prod-v1",
      "requirement": {
        "id": "req-rollback",
        "description": "Verified rollback path exists",
        "mandatory": true,
        "acceptable_kinds": ["test", "reproduction", "policy"]
      }
    },
    {
      "type": "tool_skepticism_override",
      "source_policy_pack": "sre-prod-v1",
      "tool_type": "observational_query",
      "override_skepticism": "high",
      "rationale": "Dashboard data in this org has known staleness issues"
    }
  ],
  "action_policy_override": {
    "forced_action": "require_human",
    "rationale": "Org policy: all production-adjacent SOFT_PASS needs human sign-off"
  }
}
```

## Merge rules

When multiple packs or rules are combined:

- keep the highest `stakes_override`
- union all applicable `requirement_injection` entries by `requirement.id`
- keep the strictest `action_policy_override`
- keep the highest `tool_skepticism_override` per tool type

If merge conflicts remain unresolved, fail compilation rather than silently
loosening policy.

## Safety constraints

These are mandatory:

- tier overrides only raise, never lower
- action overrides only tighten, never relax
- tool skepticism overrides only increase skepticism
- requirement injection may add obligations, not remove existing ones

## Examples

See:

- `references/examples/sre-production.yaml`
- `references/examples/research-claims.yaml`
