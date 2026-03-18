# Decision Assurance Stakes Router

Use this module first in the pipeline.
Its job is to classify the operational stakes of the claim or action and decide
whether the full assurance path is needed.

## Goal

The router produces a tiered answer to two questions:

1. How consequential is it if this output is wrong?
2. Should the pipeline fast-exit, or should it run the judge and governor?

The router is deterministic, single-pass, and stateless.

## Input signals

The router reads the top-level pipeline input, especially:

- `claim`
- `claim_type`
- `domain`
- `execution_mode`
- `target_strength`
- `impact_profile`
- `stakes_override`
- `policy_overrides`

Optional signals such as known evidence or caller-provided constraints may
refine the rationale, but the router should not require them.

## Accepted normalized values

The router expects these normalized values when the caller provides them:

- `impact_profile.scope`: `local`, `team`, `service`, `production`, or
  `external`
- `impact_profile.reversibility`: `easy`, `moderate`, `hard`, or
  `irreversible`
- `impact_profile.blast_radius`: `isolated`, `single_service`, `multi_service`,
  or `org_wide`
- `impact_profile.time_sensitivity`: `none`, `low`, `urgent`, or `immediate`
- `impact_profile.affected_assets`: array of named assets
- `stakes_override`: `LOW`, `MEDIUM`, `HIGH`, or `CRITICAL`

If `stakes_override` is present:

- respect it when it matches or raises the router's inferred tier
- do not silently use it to lower the tier unless an outer policy explicitly
  requires that downgrade

For backward compatibility, the router may still accept flat
`impact_scope` and `reversibility` aliases.
When both aliases and `impact_profile` are present, prefer `impact_profile`.

## Output shape

See `stakes-schema.json` for the machine-checkable schema.

```json
{
  "stakes_tier": "HIGH",
  "routing_decision": "assure",
  "tier_rationale": "Production-impacting action with hard reversibility and possible service disruption.",
  "routing_signals": [
    "execution_mode=auto",
    "impact_profile.scope=production",
    "impact_profile.reversibility=hard",
    "impact_profile.blast_radius=single_service"
  ]
}
```

## Tier definitions

### LOW

Use `LOW` when all of these are broadly true:

- blast radius is local or tightly bounded
- the work is easily reversible
- failure would be cheap to recover from
- no safety, legal, financial, privacy, or production boundary is crossed

Examples:

- formatting
- summarization
- cosmetic local changes
- provisional low-impact hypotheses

### MEDIUM

Use `MEDIUM` when the output could mislead or waste meaningful effort, but the
harm is still bounded and recoverable.

Examples:

- definitive coding diagnosis without production execution
- non-production access recommendation
- research summary stated too strongly

### HIGH

Use `HIGH` when the output can trigger material operational, security, or
customer impact.

Examples:

- production configuration changes
- destructive or service-affecting actions with rollback
- security-sensitive recommendations
- automated execution on shared systems

### CRITICAL

Use `CRITICAL` when failure could create severe irreversible harm or when the
domain requires exceptional accountability.

Examples:

- destructive production actions with unclear recovery
- safety-critical claims
- legal, financial, or medical decisions
- broad user-impacting approvals or denials

## Routing decision

Return one of:

- `fast_exit`
- `assure`

### `fast_exit`

Use `fast_exit` only when:

- `stakes_tier = LOW`
- the task is reversible or bounded
- the caller is not presenting a factual conclusion, diagnosis, safety
  assertion, or action recommendation as settled
- no `policy_overrides` force assurance

When the router returns `fast_exit`, the downstream output must still preserve
the full pipeline shape:

- judge fast-exits with `gate_required = false`
- judge `verdict = PASS`
- governor returns `governed_action = allow`

### `assure`

Use `assure` for all `MEDIUM`, `HIGH`, and `CRITICAL` cases, and for any `LOW`
case where policy or claim strength still warrants structured evidence review.

## Tier classification algorithm

Classify tier using impact_profile dimensions only. Do not adjust tier based
on domain keywords, evidence quality, execution mode, or absence of evidence.

Step 1: apply this bounded-case shortcut first.

If all of these are true, classify the case as `LOW` immediately:

- `scope` in `{local, team}`
- `blast_radius = isolated`
- `reversibility` in `{easy, moderate}`

Do not promote this bounded combination to `MEDIUM` just because
`reversibility = moderate`.

Step 2: otherwise classify by highest remaining impact dimension.

| Condition | Tier |
| --- | --- |
| `scope = external` OR `reversibility = irreversible` OR `blast_radius = org_wide` | `CRITICAL` |
| `scope = production` OR `reversibility = hard` OR `blast_radius = multi_service` | `HIGH` |
| `scope = service` OR `blast_radius = single_service` OR `reversibility = moderate` | `MEDIUM` |

If none of the rows above match, use `LOW`.

Step 3: if `stakes_override` is present and higher, use the override.

Step 4: do not adjust. Domain sensitivity, `execution_mode`, evidence gaps,
and claim content affect `routing_decision`, not tier.

## Tier ceiling rules

Apply these ceilings after the base classification and after any higher
`stakes_override`.

The ceiling is mandatory.
If the base classification is higher than the ceiling, replace it with the
ceiling.
Final tier = `min(base tier, applicable ceiling)`.
Do not keep or justify a higher tier once a ceiling applies.

When `blast_radius` is `isolated` or `team` and `scope` is `service` or
`team`:

- tier ceiling is `MEDIUM` regardless of domain keywords
- if `reversibility` is also `easy` or `moderate`, tier ceiling is `LOW`

When `blast_radius = single_service` and `scope` is not `org_wide`:

- tier ceiling is `HIGH` regardless of domain keywords

Domain sensitivity (`security`, `compliance`, `finance`, `medical`,
`military`) affects `routing_decision` (`assure` vs `fast_exit`) and may
support an `ESCALATE` verdict later, but it does not raise the tier ceiling.

Worked examples:

- A team-scoped, isolated cleanup or deletion with `reversibility = moderate`
  stays `LOW` even if execution is automatic. Auto execution may force
  `assure`, but it does not raise tier.
- A team-scoped, isolated standards or compliance assertion can stay `LOW`
  even when it routes to `assure`. Standards language affects routing, not
  tier.
- Missing approval, backup, regeneration, or owner-confirmation evidence does
  not raise tier. Those are judge concerns, not router inputs.
- Team scope by itself does not raise `LOW` to `MEDIUM` when blast radius is
  still isolated.
- A production security-exception request is usually `HIGH`, not `CRITICAL`,
  unless the impact profile itself reaches `external`, `irreversible`, or
  `org_wide`.

## Routing heuristics

These heuristics control the routing decision (`assure` vs `fast_exit`).
They do not raise the stakes tier.

Bias toward `assure` when any of these are true:

- `execution_mode = auto`
- `target_strength` is `definitive` or `execute`
- `impact_profile.blast_radius` is `multi_service` or `org_wide`
- `impact_profile.time_sensitivity` is `urgent` or `immediate`
- the claim is a safety assertion
- `stakes_override` is higher than the inferred tier
- `policy_overrides` require approval or auditing
- the domain includes security, privacy, finance, legal, or medical risk

## Notes

- The router does not score evidence quality.
- It should not overfit to the number of evidence items.
- If the caller provides contradictory policy signals, keep the higher tier.
