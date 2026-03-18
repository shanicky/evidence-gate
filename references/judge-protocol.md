# Decision Assurance Judge Protocol

Use this protocol when embedding the Calibrated Judge inside the Decision
Assurance pipeline or when invoking the judge directly.

## Table of contents

- [Goal](#goal)
- [Candidate schema](#candidate-schema)
- [Evidence item schema](#evidence-item-schema)
- [Requirement schema](#requirement-schema)
- [Additional judgment outputs](#additional-judgment-outputs)
- [Evidence evaluation pitfalls](#evidence-evaluation-pitfalls)
- [Tool skepticism](#tool-skepticism)
- [Tier-sensitive sufficiency](#tier-sensitive-sufficiency)
- [Verdict interpretation](#verdict-interpretation)
- [Fast-exit rule](#fast-exit-rule)
- [Canonical output](#canonical-output)
- [Minimal examples](#minimal-examples)

## Goal

The judge takes a tentative claim or action plus the current `stakes_tier`
and answers one bounded question:

**Is the explicit evidence in this invocation strong enough for the intended
claim strength or action?**

The judge stays single-pass and stateless:

1. Normalize the candidate.
2. Generate the minimum evidence obligations.
3. Evaluate only explicit evidence in scope.
4. Return one final verdict for this invocation.
5. Exit.

The judge does not collect evidence, retry, or own orchestration.

## Candidate schema

See `judge-input-template.md` for the canonical template.

```json
{
  "claim": "Disable the worker queue in production.",
  "claim_type": "action",
  "domain": "sre",
  "stakes_tier": "HIGH",
  "execution_mode": "auto",
  "target_strength": "execute",
  "known_evidence": [],
  "alternatives_checked": [],
  "available_tools": ["logs", "canary", "rollback_runbook"],
  "policy_overrides": []
}
```

### Field notes

- `claim`: Keep it specific and externally checkable.
- `claim_type`: Use `fact`, `diagnosis`, `recommendation`, `action`, or
  `safety`.
- `stakes_tier`: Use `LOW`, `MEDIUM`, `HIGH`, or `CRITICAL`.
- `execution_mode`:
  - `informational`
  - `advisory`
  - `auto`
- `target_strength`:
  - `exploratory`
  - `provisional`
  - `definitive`
  - `execute`
- `policy_overrides`: Caller-supplied rules such as
  `"destructive actions require human approval"`.

When invoked with only a claim, keep the old v1 behavior:

- infer `claim_type`, `domain`, `execution_mode`, and `target_strength`
- default `stakes_tier` to `MEDIUM`
- treat absent evidence as an explicit lack of evidence, not as hidden support

## Evidence item schema

Model every explicit evidence artifact with a compact record.

```json
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
```

### Recommended evidence kinds

- `observation`
- `measurement`
- `log`
- `trace`
- `test`
- `reproduction`
- `code_path`
- `policy`
- `approval`
- `external_source`
- `human_confirmation`
- `counterevidence`

### Reliability guidance

Use `high`, `medium`, or `low`.
If the caller cannot justify a tool output's reliability, treat it as an
evaluation gap instead of silently promoting it to evidence.

### Provenance guidance

These optional provenance fields make the judge materially better:

- `timestamp`: ISO 8601 capture time for the evidence
- `environment`: `local`, `staging`, `production`, or `external`
- `freshness`: `current`, `recent`, `stale`, or `unknown`
- `independence_group`: shared source bucket for independence analysis

Use provenance this way:

- stale evidence should lower confidence, especially for operational claims
- environment mismatch should count against scope transfer
- evidence items in the same `independence_group` do not count as independent
  corroboration
- missing provenance does not invalidate the evidence, but it should keep the
  requirement from being overstated

## Requirement schema

Generate only the minimum obligations needed for the claim or action at the
current tier.

Generate requirements only for the core risks of the claim or action at the
current tier. Do not invent requirements for evidence categories that the
caller did not provide and that are not strictly mandatory at this tier.

At `LOW` and `MEDIUM`, 2-3 requirements are typical.
At `HIGH`, 3-4 requirements are typical.
At `CRITICAL`, 3-5 requirements are typical.

If the caller provides evidence that covers the core risks, do not create
additional requirements solely to find gaps. Specifically:

- Do not add an "auto-execution authorization" requirement unless the caller's
  `policy_overrides` explicitly demand it.
- Do not add a "rollback plan" requirement when the caller already provides
  evidence of a successful rollback drill or recovery path.
- Do not split one risk into multiple requirements to inflate the count.
- Do not create a second approval or "real-time confirmation token"
  requirement when a named qualified approval artifact already covers the
  authority risk.
- Do not create a separate rollback or recovery requirement when the caller
  already provides a successful staged drill or validated rollback path that
  covers the same core risk.

When evidence items map cleanly to the core requirements, mark those
requirements `satisfied` and move on.

```json
{
  "id": "req-isolation",
  "description": "Show an isolating check that the worker queue is the actual outage driver.",
  "mandatory": true,
  "acceptable_kinds": ["test", "reproduction", "measurement"],
  "status": "missing",
  "evidence_refs": [],
  "notes": "Temporal correlation alone is not enough at HIGH stakes."
}
```

### Requirement status values

- `satisfied`
- `missing`
- `conflicting`
- `not_applicable`

## Additional judgment outputs

The judge always returns two calibration fields and one residual-risk field in
addition to the v1 verdict:

### `source_independence`

Estimate whether the supporting evidence is meaningfully independent.

- `high`: multiple independent methods or sources converge
- `medium`: some corroboration exists, but key support still clusters together
- `low`: the case rests on one source, one method, or one pipeline
- `not_applicable`: fast exit or no supporting evidence was evaluated

### `confidence_calibration`

Return one of:

- `high`: the evidence cleanly matches the requested strength for the tier
- `medium`: the case is usable but needs bounded caveats
- `low`: the evidence only supports a downgrade, a block, or escalation
- `not_applicable`: fast exit, so no calibration pass was needed

### `residual_risk`

Describe the remaining risk even after the current verdict and governance
result.

- `description`: short explanation of what can still go wrong
- `severity = none`: no meaningful residual risk recorded for the current case
- `severity = low`: bounded risk remains, but routine mitigation is enough
- `severity = medium`: meaningful operational risk remains and should be
  monitored or mitigated explicitly
- `severity = high`: substantial residual risk remains even if the verdict is
  actionable

Residual risk is not the same as unsupported evidence.
`PASS` and `SOFT_PASS` may still carry non-`none` residual risk when the action
is justified but ongoing exposure remains.

## Evidence evaluation pitfalls

When a pitfall applies, do **not** mark the requirement `satisfied`.
Mark it `missing` or `conflicting`.

- **Temporal correlation is not causation.**
  "X happened after Y" does not satisfy causation or remediation requirements.
- **Single-source confirmation is weak confirmation.**
  One log stream, one chart, or one witness should not satisfy a central
  requirement when the tier expects corroboration.
- **Scope mismatch breaks transfer.**
  Dev evidence does not automatically justify a production claim or action.
- **Absence is not active verification.**
  "No complaints" does not prove safety.
- **Unrated tool output is not self-authenticating.**
  If the supporting evidence comes from a tool or model with unknown
  reliability, treat that reliability check as missing.

## Tool skepticism

Apply default skepticism by tool type when evidence originates from tooling.

- `deterministic_check`
  - examples: linter, type checker, schema validator
  - skepticism: low
  - guidance: can directly satisfy a narrow requirement when scope matches
- `controlled_test`
  - examples: unit test, integration test, canary
  - skepticism: low
  - guidance: strong evidence under controlled conditions
- `observational_query`
  - examples: log query, metrics dashboard, trace
  - skepticism: medium
  - guidance: verify scope match, freshness, and causality before treating it
    as central proof
- `search_retrieval`
  - examples: web search, RAG, document retrieval
  - skepticism: high
  - guidance: do not let it satisfy a core requirement by itself at `HIGH` or
    `CRITICAL` stakes
- `model_inference`
  - examples: LLM output, ML model score, vendor model
  - skepticism: high
  - guidance: never treat it as self-authenticating; require external
    validation
- `human_report`
  - examples: chat message, email, verbal statement
  - skepticism: medium
  - guidance: useful context, but one person's report is not independent
    confirmation

## Tier-sensitive sufficiency

The same evidence can justify different outcomes at different tiers.
Apply stricter sufficiency as stakes rise.

### LOW

- Allow fast exit for clearly reversible, bounded, low-impact outputs.
- If gating still occurs, minimal direct support can be enough for `PASS`.

### MEDIUM

- `PASS` requires all mandatory requirements satisfied and no unresolved
  central conflict.
- `SOFT_PASS` is acceptable for advisory output or weaker wording.

### HIGH

- `PASS` requires all mandatory requirements satisfied.
- Central claims should have at least one independent corroborating signal.
- Operational safety checks must cover rollback, blast radius, or approval when
  relevant.

### CRITICAL

- `PASS` requires all mandatory requirements satisfied with no unresolved
  contradiction on central risk.
- Independent corroboration is expected for core claims.
- Missing policy, approval, or safety ownership usually prevents `PASS`.
- If the skill cannot responsibly judge the domain-specific risk, use
  `ESCALATE`.

## Verdict interpretation

### Verdict decision tree

Follow this sequence. Stop at the first matching condition.

1. **Fast-exit path**: If the router returned `fast_exit`, return `PASS`.
2. **ESCALATE check**: Does the claim require specialist authority or domain
   certification that no amount of additional generic evidence can provide?
   Use the specialist-authority checklist below. If yes, return `ESCALATE`.
3. **CONFLICT check**: Do evidence items actively contradict each other on the
   central question? Not absence: active contradiction. If yes, return
   `CONFLICT`.
4. **PASS check**: Are all mandatory requirements `satisfied` with no
   unresolved central conflict? If yes, return `PASS`. Do not downgrade
   because the tier feels high, because optional gaps exist, or because you
   invented additional requirements beyond the tier's typical count.
5. **SOFT_PASS check**: Is at least one mandatory requirement `satisfied`, and
   can the caller still safely produce a weaker or advisory output? If yes,
   return `SOFT_PASS`.
6. **Otherwise**: return `BLOCK`.

Do not skip steps.
Do not re-evaluate a higher step after reaching a lower one.

Use exactly these verdicts:

- `PASS`: Evidence is sufficient for the requested strength at this tier.
- When all mandatory requirements are `satisfied` and no central conflict is
  unresolved, return `PASS` even at `HIGH` or `CRITICAL` tiers. Do not
  downgrade to `SOFT_PASS` because the tier feels high. The tier-sensitive
  sufficiency rules already set a higher bar for what counts as `satisfied`;
  once that bar is met, the verdict is `PASS`.
- `confidence_calibration` is an informational output. It does not override the
  verdict. If all mandatory requirements are satisfied and no central conflict
  exists, the verdict is `PASS` even when
  `confidence_calibration.level = medium`.
- If all mandatory requirements are satisfied and no central conflict exists,
  do not return `SOFT_PASS` or `BLOCK`.
- Do not let an unsatisfied optional requirement change `PASS` to `SOFT_PASS`
  or `BLOCK`.
- If the only remaining gap is optional environment alignment, a nice-to-have
  follow-up, or another non-mandatory confirmation, keep `PASS`.
- Positive examples of `PASS`:
  - a service-scoped diagnosis where reproduction, code-path confirmation, and
    alternative elimination are all satisfied
  - a production action where isolation, rollback, blast-radius review, and
    approval are all satisfied
  - a CRITICAL production key rotation where the core risks are covered by the
    provided evidence set and no central contradiction remains
  - when four explicit evidence items already cover compromise confirmation,
    recovery plan, dependency check, and accountable approval, that is `PASS`
    at `CRITICAL`; do not invent extra requirements such as a post-incident
    review timeline or secondary approval and then downgrade because they are
    missing
- `SOFT_PASS`: Evidence supports a weaker statement, advisory output, or
  reversible continuation.
- Use `SOFT_PASS` when at least one mandatory requirement is `satisfied` and
  the concern has a reasonable evidentiary basis, even if other requirements
  are still missing. The caller may surface the concern in weakened or
  advisory form.
- If at least one mandatory requirement is satisfied and the caller can still
  safely give a weaker or advisory output, prefer `SOFT_PASS` over `BLOCK`.
- High- or critical-tier mitigations with some satisfied requirements and a
  safe human-review path are usually `SOFT_PASS`, not `BLOCK`.
- A finance or payout freeze concern with partial support and ordinary
  operational review gaps is usually `SOFT_PASS`, not `ESCALATE`.
- A shared-service staging change with one legitimate support signal but
  missing coordination artifacts is usually `SOFT_PASS`, not `BLOCK`.
- Use `BLOCK` when zero mandatory requirements are `satisfied`, or the
  evidentiary basis is so thin that even an advisory statement is not
  justified. A single unverified report without reproduction or scope
  assessment is typically a `BLOCK`, not a `SOFT_PASS`.
- When counterevidence contradicts the claim but a rollback plan or partial
  mitigation is in place, `SOFT_PASS` is usually more appropriate than
  `BLOCK` because the advisory output adds value.
- Positive examples of `SOFT_PASS`:
  - one production mitigation requirement is satisfied, others remain missing,
    and the safest output is a bounded recommendation for human review
  - a payout or freeze concern has partial support and meaningful
    counterevidence, so advisory caution is justified but a final denial or
    freeze is not
  - a shared-service staging change has one legitimate support signal but
    lacks coordination artifacts, so the caller may surface the concern in
    advisory form only
- `BLOCK`: Evidence is insufficient for the requested claim or action.
- `CONFLICT`: Central evidence points in materially different directions.
- Use `CONFLICT` when evidence items actively point in different directions on
  a central question, not when evidence is simply absent. If one signal
  supports the claim and another signal contradicts it, that is `CONFLICT`.
  If there is only one weak signal and everything else is missing, that is
  `BLOCK`.
- `ESCALATE`: The skill cannot responsibly resolve the remaining uncertainty and
  the case must move to a human or specialist owner.

`ESCALATE` is for capability or authority gaps, not just thin evidence.
Use it when the correct next move is specialist review rather than additional
generic evidence gathering.

Do not use `ESCALATE` when the gap is ordinary missing evidence (approvals,
tests, reviews). Use `BLOCK` and list the missing evidence in
`next_evidence_actions`. Reserve `ESCALATE` for cases where the missing piece
is specialist authority or domain expertise that generic evidence gathering
cannot provide.

Use this specialist-authority checklist:

- Does the claim require a qualified domain sign-off that only a designated
  specialist can provide?
- Would collecting more generic artifacts still leave the skill unable to make
  the final determination without that specialist?
- Is the missing decision fundamentally about authority, certification, or
  standards interpretation rather than ordinary evidence sufficiency?

If the answer is yes to any of these, prefer `ESCALATE`.

If the missing piece is specialist authority or delegated approval authority,
do not use `BLOCK`.

Named domains that normally require `ESCALATE` when the qualified authority is
missing:

- tax correctness or tax treatment approval
- MIL-STD, certification, or standards-compliance correctness
- production security exception approval by a qualified security owner

To decide between `BLOCK` and `ESCALATE`, ask: if the caller gathered all the
evidence listed in `next_evidence_actions`, could the skill then issue a
confident verdict? If yes, use `BLOCK`. If the answer is no because the claim
requires domain authority or specialist certification that generic evidence
gathering cannot provide, use `ESCALATE`.

Examples of `BLOCK`:

- "Delete the production backup" with no retention-policy approval.
  The gap is a missing approval, not a specialist judgment.
- "Approve this security exception" with only a vendor summary.
  The gap is missing independent validation and change-control evidence.

Examples of `ESCALATE`:

- "This tax treatment is correct" with no qualified tax opinion.
  The gap is domain authority that the skill cannot fabricate.
- "This waveform threshold is MIL-STD compliant" with only an unreviewed
  local parser. The gap is qualified standards-engineering authority.
- "This medical triage threshold is safe" with only a vendor model score.
  The gap is clinical authority that no amount of generic evidence replaces.
- "Approve this production security exception" without a qualified security
  owner or risk-signoff authority. The gap is delegated security authority,
  not just another evidence artifact.

## Fast-exit rule

The judge preserves the v1 fast-exit contract:

- `gate_required = false`
- `verdict = PASS`
- `source_independence.rating = not_applicable`
- `confidence_calibration.level = not_applicable`
- `residual_risk.severity = none`
- `residual_risk.mitigations = []`
- `requirements = []`
- `missing_evidence = []`
- `conflicting_evidence = []`

Fast exit is valid only when the caller's output is sufficiently low-stakes or
bounded that no structured evidence gate is needed.

## Canonical output

Return JSON matching `judge-output-template.md`.
Validate against `judge-verdict-schema.json`.
Keep every top-level field on every invocation.

## Minimal examples

### High-stakes action with downgrade

Candidate:

```json
{
  "claim": "Disable the worker queue in production.",
  "claim_type": "action",
  "stakes_tier": "HIGH",
  "execution_mode": "auto",
  "target_strength": "execute",
  "known_evidence": [
    {
      "id": "ev-1",
      "summary": "Queue latency spiked during the outage.",
      "kind": "measurement",
      "source": "dashboard",
      "artifact_ref": "grafana/queue-latency",
      "reliability": "medium",
      "supports": ["req-isolation"],
      "contradicts": []
    }
  ]
}
```

Likely outcome:

- `req-isolation` remains `missing`
- `source_independence.rating = low`
- `confidence_calibration.level = low`
- verdict downgrades to `SOFT_PASS` or `BLOCK`

### Specialist escalation

Candidate:

```json
{
  "claim": "This medical triage threshold is safe for patient release.",
  "claim_type": "safety",
  "domain": "medical",
  "stakes_tier": "CRITICAL",
  "execution_mode": "advisory",
  "target_strength": "definitive",
  "known_evidence": [
    {
      "id": "ev-1",
      "summary": "One vendor model score suggests low risk.",
      "kind": "external_source",
      "source": "vendor model",
      "artifact_ref": "vendor-report-18",
      "reliability": "low",
      "supports": ["req-clinical-safety"],
      "contradicts": []
    }
  ]
}
```

Likely outcome:

- mandatory safety requirements stay `missing`
- tool reliability is unresolved
- the skill returns `ESCALATE` for qualified human review
