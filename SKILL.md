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
  - use `scripts/map_action.py` as the runtime authority
  - treat `references/action-map.md` as the human-readable mirror

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
- the router classifies tier using the algorithm in
  `references/stakes-router.md`
- treat `scripts/classify_tier.py` as the runtime authority when local script
  execution is available
- the tier algorithm uses only `impact_profile` dimensions; do not adjust tier
  based on domain keywords, execution mode, or evidence quality
- do not raise tier based on evidence quality or `execution_mode`
- use normalized `impact_profile` values:
  `scope`, `reversibility`, `blast_radius`, `time_sensitivity`,
  `affected_assets`
- a root-of-trust asset inside `affected_assets` may raise a shared
  production/external case to `CRITICAL`; see `scripts/classify_tier.py`
- bias upward when policy overrides exist
- do not inspect hidden reasoning

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

Use exactly: `allow`, `allow_advisory`, `require_human`, `block`, `escalate`.

#### Mapping rules

Apply the fixed mapping from `scripts/map_action.py`.
Use `references/action-map.md` only as a human-readable mirror of the same
table.

If the structured input includes `action_policy_override`, apply the base map
first and then keep the stricter resulting action.
Never use the override to loosen the base map.

Important defaults: `PASS -> allow`, `BLOCK -> block`, `ESCALATE -> escalate`,
and both `SOFT_PASS` and `CONFLICT` map to `allow_advisory` at `LOW` or
`MEDIUM`, then to `require_human` at `HIGH` or `CRITICAL`.

The action map is a lookup table. The governor must output exactly the cell
value from `references/action-map.md`. It must not adjust the result based on
its own judgment. `PASS` at any tier, including `CRITICAL`, maps to `allow`.

#### Audit record

Every governed action must nest an `audit_record` object inside the `action`.
Do not flatten these fields to the action top level.

The `audit_record` object must contain:

- `rule_id`: exactly `VERDICT:TIER` (for example `PASS:CRITICAL` or
  `BLOCK:HIGH`)
- `policy_source`: always `"references/action-map.md"`
- `verdict`: the judge verdict copied from `judgment.verdict`
- `stakes_tier`: the router tier copied from `stakes.stakes_tier`
- `decision_basis`: one-sentence mapping rationale
- `required_followups`: array of explicit follow-ups

The action top level has exactly three keys:

- `governed_action`
- `audit_record`
- `caller_instructions`

Do not add top-level `rule_id`, `verdict`, `stakes_tier`, `verdict_input`, or
`stakes_tier_input` fields to `action`.

## Recommended workflow

Use this exact control shape unless a stricter outer policy exists.

When local script execution is available, the pipeline must use scripts for
deterministic steps:

1. Run `scripts/classify_tier.py` for tier classification. Do not re-classify
   in prose.
2. Use the script-computed tier as input to the judge.
3. When the runtime invokes the model in judge-only mode, send
   `references/judge-protocol.md` and
   `references/judge-output-template.md` as the system prompt and return only
   the `judgment` JSON object.
4. After the judge returns a verdict, run `scripts/map_action.py` for action
   mapping. Do not re-map in prose.

When scripts are not available, follow the pseudocode in
`references/stakes-router.md` and the lookup table in
`references/action-map.md` as closely as possible.

1. Normalize the candidate claim or action.
2. Route stakes before judging evidence.
3. If the router returns `fast_exit`, emit the full pipeline envelope with a
   judge fast exit and `action.governed_action = allow`.
4. If the router returns `assure`, run the judge.
5. Generate only the minimum operational evidence obligations.
6. Evaluate only evidence explicitly available in the current invocation.
7. Produce one final verdict.
8. Pass `(verdict, stakes_tier)` into `scripts/map_action.py` when local script
   execution is available; otherwise mirror the same lookup table exactly.
9. Assemble the full envelope. In judge-only mode, the runtime owns this step.
10. Run `scripts/validate.py` with the final JSON on stdin when local script
    execution is available.
11. If validation fails, fix each reported violation and re-emit.
12. Do not return the output until validation passes.

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

Worked examples live in `references/quick-examples.md`.
Use them as output-shape references, not as extra rules.
