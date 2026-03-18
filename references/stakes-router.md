# Decision Assurance Stakes Router

Use this module first in the pipeline.
Its job is to classify the operational stakes of the claim or action and decide
whether the full assurance path is needed.

## Goal

The router produces a tiered answer to two questions:

1. How consequential is it if this output is wrong?
2. Should the pipeline fast-exit, or should it run the judge and governor?

The router is deterministic, single-pass, and stateless.
When local script execution is available, `scripts/classify_tier.py` is the
runtime authority for `stakes_tier`.

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

Use `fast_exit` only when all of these are true:

1. `stakes_tier = LOW`
2. the task is reversible or bounded
3. `known_evidence` is empty or absent (no structured evidence items
   provided)
4. the caller is not presenting a factual conclusion, diagnosis, safety
   assertion, or action recommendation as settled
5. no `policy_overrides` force assurance

If `known_evidence` contains one or more items, always route to `assure`
regardless of tier.
Evidence items exist to be evaluated.

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
on domain keywords, execution mode, evidence gaps, or claim content.
When local script execution is available, run `scripts/classify_tier.py` and
use its output directly.
The pseudocode below is the reference specification that the script
implements. Follow it step by step.

```text
function classify_tier(impact_profile, stakes_override):

  scope = impact_profile.scope
  reversibility = impact_profile.reversibility
  blast_radius = impact_profile.blast_radius
  affected_assets = impact_profile.affected_assets

  // Step 1: bounded shortcut
  if scope in {local, team}
     AND blast_radius == isolated
     AND reversibility in {easy, moderate}:
    computed = LOW
    goto step3

  // Step 2: highest-impact dimension
  if scope in {production, external}
     AND blast_radius in {multi_service, org_wide}
     AND affected_assets indicate shared root-of-trust infrastructure:
    computed = CRITICAL
  else if scope == external
       OR reversibility == irreversible
       OR blast_radius == org_wide:
    computed = CRITICAL
  else if scope == production
       OR reversibility == hard
       OR blast_radius == multi_service:
    computed = HIGH
  else if scope == service
       OR blast_radius == single_service
       OR reversibility == moderate:
    computed = MEDIUM
  else:
    computed = LOW

  step3:
  // Step 3: stakes_override can only raise
  if stakes_override is present AND rank(stakes_override) > rank(computed):
    computed = stakes_override

  // Step 4: ceiling (mandatory, overrides even stakes_override)
  ceiling = null
  if blast_radius in {isolated, team} AND scope in {service, team}:
    ceiling = MEDIUM
    if reversibility in {easy, moderate}:
      ceiling = LOW
  else if blast_radius == single_service:
    ceiling = HIGH

  if ceiling is not null:
    final = min(computed, ceiling)
  else:
    final = computed

  return final
```

Do not adjust tier for any reason not in this algorithm.
Domain keywords, execution_mode, evidence gaps, and claim content affect
`routing_decision` (`assure` vs `fast_exit`), not tier.

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
