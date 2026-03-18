---
name: "decision-assurance"
description: "Routes a tentative claim or action through stakes classification, calibrated evidence judgment, and action governance. TRIGGER when the agent is about to present a root-cause diagnosis as settled, make a safety assertion, recommend or execute a high-impact action, approve or deny a consequential request, or state a strong conclusion from thin evidence. DO NOT TRIGGER for pure formatting, summarization, brainstorming, or clearly low-risk reversible work unless local policy requires assurance."
---

# Decision Assurance

Use this skill to add one bounded governance pass to an existing workflow.

The skill answers a narrow question:

**What is the strongest responsible thing the caller may say or do, given the
explicit evidence currently available?**

It does not replace domain reasoning.
It does not take over orchestration.
It does not run a retry loop.

## Core model

Run a single stateless pipeline:

1. **Stakes Router**
   - classify operational stakes as `LOW`, `MEDIUM`, `HIGH`, or `CRITICAL`
   - choose `fast_exit` or `assure`
2. **Calibrated Judge**
   - define the minimum evidence obligations
   - evaluate only explicit evidence in scope
   - return `PASS`, `SOFT_PASS`, `BLOCK`, `CONFLICT`, or `ESCALATE`
3. **Action Governor**
   - deterministically map `(verdict, stakes_tier)` to
     `allow`, `allow_advisory`, `require_human`, `block`, or `escalate`

Return one final structured output and exit.

## Invariants

These are mandatory:

- **Single-pass**
  - no second gate round
  - no retry loop
  - no hidden collection cycle
- **Stateless**
  - no persistent files
  - no cross-call memory
  - no implicit carry-over from prior invocations
- **Structured**
  - always return the full top-level pipeline shape
  - do not silently drop fields
- **Fast-exit preserved**
  - `routing_decision = fast_exit` must still return the full envelope
  - `judgment.gate_required = false` implies `judgment.verdict = PASS`
  - fast exit means empty requirements, missing evidence, and conflicting
    evidence
  - fast exit also means `judgment.residual_risk.severity = none`
- **Deterministic governance**
  - do not improvise a new action map at runtime
  - use `references/action-map.md`

## Scope

This skill governs the agent's own claim strength and action strength.

It is not:

- content moderation
- user intent classification
- a legal or compliance decision engine
- a replacement for domain expertise
- a multi-step verifier

## When to use

Use this skill when one or more of these are true:

- the caller is about to present a root-cause diagnosis as settled
- the caller is about to make a safety assertion
- the caller is about to recommend or execute a destructive or high-impact step
- the caller is about to approve or deny access, rollout, rollback, deletion,
  or production change
- the current position depends on one signal, one tool output, or one source
- competing explanations have not been checked
- the user explicitly asks for an evidence-backed answer
- local policy requires auditable justification

## When not to use

Do not use this skill when:

- the task is purely formatting
- the task is straightforward summarization
- the caller is brainstorming possibilities and not presenting them as settled
- the work is trivially reversible and low impact
- the caller already has a stronger assurance layer for the same step

## Operating posture

Treat every claim or action as tentative until the pipeline finishes.

Prefer:

- bounded evidence obligations
- direct evaluation of explicit artifacts
- downgrade over overclaiming
- human review over fabricated certainty

Do not:

- claim hidden reasoning as evidence
- collect evidence inside a loop
- treat policy silence as approval
- turn generic uncertainty into `ESCALATE`

## Inputs

The only required input is the claim or action under consideration.

The slash-prefixed examples below illustrate skill-style invocation syntax.
Non-skill consumers may pass the same fields directly as structured input.

Examples:

- `/decision-assurance "The root cause is a nil dereference in request parsing."`
- `/decision-assurance "Disable the worker queue in production."`
- `/decision-assurance "This access change is safe under policy."`

When the caller provides only a claim, infer reasonable defaults from context.

Typical inferred fields:

- `claim_type`
- `domain`
- `execution_mode`
- `target_strength`
- `impact_profile`

For backward compatibility, callers may still send top-level `impact_scope` and
`reversibility` aliases.
When both alias fields and `impact_profile` are present, use `impact_profile`
as the source of truth.

Optional caller-controlled overrides for structured input:

- `stakes_override`
  - pin or raise the stakes tier when an outer workflow has already classified
    the case
- `action_policy_override`
  - reserve a stricter final action such as `require_human`, `block`, or
    `escalate`

When the caller wants deterministic control, use:

- `references/pipeline-input-template.md`

## Output

Return JSON matching:

- `references/pipeline-output-template.md`

Validate against:

- `references/pipeline-schema.json`

Always keep these top-level objects present:

- `stakes`
- `judgment`
- `action`

## Pipeline contract

### 1. Stakes Router

Use `references/stakes-router.md` and `references/stakes-schema.json`.

The router decides:

- `stakes_tier`
- `routing_decision`
- `tier_rationale`
- `routing_signals`

#### Router guidance

- classify stakes based on consequence if wrong, not based on how confident the
  caller sounds
- consider blast radius, reversibility, execution mode, and sensitive domains
- tier is classified by `impact_profile` dimensions alone; see the tier
  classification algorithm in `references/stakes-router.md`
- if a tier ceiling rule applies in `references/stakes-router.md`, it is
  mandatory and replaces any higher tentative tier
- do not raise tier based on domain keywords, evidence quality, or
  `execution_mode`
- accept normalized `impact_profile` values:
  `scope`, `reversibility`, `blast_radius`, `time_sensitivity`,
  `affected_assets`
- if `stakes_override` is present, treat it as a same-or-higher tier floor
- bias upward when policy overrides exist
- do not inspect hidden reasoning

Tier ceiling rules:

- if `blast_radius` is `isolated` and `scope` is `team` or `service`, tier
  ceiling is `MEDIUM`
- if that same case also has `reversibility` equal to `easy` or `moderate`,
  tier ceiling is `LOW`
- if `blast_radius` is `single_service` and the scope is not `external`, tier
  ceiling is `HIGH`
- once a ceiling applies, replace any higher tentative tier with the ceiling

#### Fast-exit conditions

Use `fast_exit` only when all of these are true:

- the case is `LOW`
- the work is reversible or tightly bounded
- the caller is not presenting a factual conclusion, diagnosis, safety
  assertion, or action recommendation as settled
- no destructive, safety-critical, or external-impact action is being proposed
- no policy override forces assurance

When the router returns `fast_exit`, still return the full pipeline envelope.
For fast exit, set:

- `judgment.source_independence.rating = not_applicable`
- `judgment.confidence_calibration.level = not_applicable`
- `judgment.residual_risk.severity = none`

### 2. Calibrated Judge

Use:

- `references/judge-protocol.md`
- `references/judge-input-template.md`
- `references/judge-output-template.md`
- `references/judge-verdict-schema.json`

The judge evolves the old evidence gate into a tier-aware evaluator.

It must:

- preserve the single-pass model
- preserve the fast-exit contract
- keep the full structured output shape
- evaluate only explicit evidence in the current invocation
- generate only `2-5` concrete requirements unless the case is unusually broad

#### Judge outputs

The judge always returns:

- `gate_required`
- `gate_reason`
- `candidate_summary`
- `stakes_tier`
- `requirements`
- `missing_evidence`
- `conflicting_evidence`
- `sufficiency_rule`
- `source_independence`
- `confidence_calibration`
- `residual_risk`
- `verdict`
- `allowed_next_actions`
- `blocked_next_actions`
- `fallback_behavior`
- `suggested_wording`
- `next_evidence_actions`

#### Verdict meanings

- `PASS`
  - the evidence supports the requested claim or action at this tier
- `SOFT_PASS`
  - the evidence supports only weaker wording, advisory continuation, or
    reversible next steps
- `BLOCK`
  - the evidence does not justify the requested strength or action
- `CONFLICT`
  - central evidence points in materially different directions
- `ESCALATE`
  - the skill cannot responsibly resolve the remaining uncertainty and the case
    must move to a human or specialist owner

#### Tier-sensitive judging

As stakes rise, the judge should expect:

- stronger corroboration
- tighter scope matching
- clearer rollback or approval evidence
- less tolerance for unresolved contradiction

#### Source independence

Always return `source_independence` as an object:

- `rating`
- `rationale`

Evaluate whether the support is independent.

Typical weak patterns:

- all support comes from one dashboard pipeline
- all support comes from one model or one opaque tool
- all support comes from one person's statement

If independence is weak, do not silently treat repeated signals as separate
proof.

#### Confidence calibration

Always return `confidence_calibration` as an object:

- `level`
- `rationale`

Use `level` values:

- `high`
  - clean evidence coverage for the requested strength
- `medium`
  - usable but requires caveats
- `low`
  - only downgrade, block, or escalation is justified
- `not_applicable`
  - fast exit, so no calibration pass was needed

#### Residual risk

Always return `residual_risk` as an object:

- `description`
- `severity`
- `mitigations`

Use residual risk to describe what can still go wrong even when the current
verdict and governance action are acceptable.
`PASS` does not imply zero residual risk.

#### Required pitfalls

Do not mark a requirement `satisfied` when any of these apply:

- temporal correlation without causal isolation
- single-source confirmation for a central claim
- scope mismatch across environment, time window, or population
- passive lack of complaints instead of active verification
- tool output with unassessed reliability
- high-skepticism tool outputs (`search_retrieval`, `model_inference`) treated
  as if they were independent proof

#### Downgrade policy

If the evidence is insufficient, prefer one of:

- weaker wording
- advisory-only output
- request for bounded additional checks
- human review

Do not let the caller present a settled diagnosis or execute a high-impact step
when the evidence only supports a tentative statement.

Verdict boundary rules:

- if all mandatory requirements are satisfied and no central conflict remains,
  return `PASS`
- an unsatisfied optional requirement must not downgrade `PASS`
- if at least one mandatory requirement is satisfied and advisory output is
  still useful, prefer `SOFT_PASS` over `BLOCK`
- if the missing piece is specialist or delegated approval authority, use
  `ESCALATE`, not `BLOCK` (see `references/judge-protocol.md` for named
  specialist-authority domains and worked examples)

### 3. Action Governor

Use:

- `references/action-governor.md`
- `references/action-map.md`
- `references/action-output-template.md`
- `references/action-schema.json`

The governor converts the verdict into an execution policy.

#### Governed actions

- `allow`
- `allow_advisory`
- `require_human`
- `block`
- `escalate`

#### Mapping rules

Apply the fixed mapping from `references/action-map.md`.

If the structured input includes `action_policy_override`, apply the base map
first and then keep the stricter resulting action.
Never use the override to loosen the base map.

Important defaults:

- `PASS` always maps to `allow`
- `BLOCK` always maps to `block`
- `ESCALATE` always maps to `escalate`
- `SOFT_PASS` and `CONFLICT` map to `allow_advisory` for `LOW` and `MEDIUM`
- `SOFT_PASS` and `CONFLICT` map to `require_human` for `HIGH` and `CRITICAL`

The action map is a lookup table. The governor must output exactly the cell
value from the map. It must not adjust the result based on its own judgment.
`PASS` at any tier, including `CRITICAL`, maps to `allow`.

<!-- This table is duplicated in references/action-map.md. Keep both in sync. -->

Inline action map:

| verdict | LOW | MEDIUM | HIGH | CRITICAL |
| --- | --- | --- | --- | --- |
| `PASS` | `allow` | `allow` | `allow` | `allow` |
| `SOFT_PASS` | `allow_advisory` | `allow_advisory` | `require_human` | `require_human` |
| `BLOCK` | `block` | `block` | `block` | `block` |
| `CONFLICT` | `allow_advisory` | `allow_advisory` | `require_human` | `require_human` |
| `ESCALATE` | `escalate` | `escalate` | `escalate` | `escalate` |

Read the verdict row and the tier column. The cell is the governed action.

#### Audit record

Every governed action must include:

- the rule identifier
- the policy source
- the verdict
- the stakes tier
- the mapping rationale
- explicit follow-ups

## Recommended workflow

Use this exact control shape unless a stricter outer policy exists.

1. Normalize the candidate claim or action.
2. Route stakes before judging evidence.
3. If the router returns `fast_exit`, emit the full pipeline envelope with a
   judge fast exit and `action.governed_action = allow`.
4. If the router returns `assure`, run the judge.
5. Generate only the minimum operational evidence obligations.
6. Evaluate only evidence explicitly available in the current invocation.
7. Produce one final verdict.
8. Pass `(verdict, stakes_tier)` into the governor.
9. Return the full envelope and stop.

## Allowed inferences

Reasonable inference is allowed for:

- claim classification
- coarse domain classification
- reversibility
- likely impact scope

Do not infer:

- missing evidence that was never provided
- approval that was never stated
- independence between sources that share one pipeline
- tool reliability without an explicit basis

## Suggested caller behavior after output

If `action.governed_action = allow`, the caller may proceed.

If `action.governed_action = allow_advisory`, the caller should:

- weaken language
- avoid auto-execution
- surface uncertainty clearly

If `action.governed_action = require_human`, the caller should:

- prepare the recommendation
- stop short of final execution or definitive approval
- route to human review

If `action.governed_action = block`, the caller should:

- not present or execute the requested claim or action
- use `next_evidence_actions` to explain what would change the result

If `action.governed_action = escalate`, the caller should:

- hand off to a qualified human or specialist owner
- avoid replacing specialist review with generic extra checks

## Integration defaults

Apply these defaults unless the caller supplies stricter policy:

1. Gate only at conclusion points or before consequential actions.
2. Prefer small, concrete requirement sets.
3. Keep requirements operational and artifact-checkable.
4. Keep next steps bounded to the smallest useful set.
5. Keep low-risk cases quiet through fast exit.
6. Keep domain ownership with the caller.

## Editing contract

When changing this skill, keep these contract families aligned:

- Stakes Router:
  `SKILL.md`, `references/stakes-router.md`, `references/stakes-schema.json`
- Calibrated Judge:
  `SKILL.md`, `references/judge-protocol.md`,
  `references/judge-input-template.md`,
  `references/judge-output-template.md`,
  `references/judge-verdict-schema.json`
- Action Governor:
  `SKILL.md`, `references/action-governor.md`,
  `references/action-map.md`, `references/action-output-template.md`,
  `references/action-schema.json`
- Pipeline:
  `SKILL.md`, `references/pipeline-input-template.md`,
  `references/pipeline-output-template.md`,
  `references/pipeline-schema.json`

## Quick examples

### Low-risk fast exit

Input:

- "Reformat this JSON file with 2-space indentation."

Expected shape:

- `stakes.routing_decision = fast_exit`
- `judgment.gate_required = false`
- `judgment.verdict = PASS`
- `action.governed_action = allow`

### High-stakes downgrade

Input:

- "Disable the worker queue in production."
- one correlation chart
- no rollback proof

Expected shape:

- `stakes.stakes_tier = HIGH`
- `judgment.verdict = SOFT_PASS` or `BLOCK`
- `action.governed_action = require_human` or `block`

### Critical escalation

Input:

- "This medical release threshold is safe."
- one opaque vendor model output

Expected shape:

- `stakes.stakes_tier = CRITICAL`
- `judgment.verdict = ESCALATE`
- `action.governed_action = escalate`
