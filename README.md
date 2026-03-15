# Evidence Gate

Evidence Gate is a stateless, single-pass skill for checking whether a strong claim or high-impact action is sufficiently supported by explicit evidence.

## Purpose

Use this skill when an agent is about to:

- present a root-cause diagnosis as settled
- make a safety assertion
- recommend or execute a high-impact action
- state a strong conclusion based on limited signals

The skill does not replace domain logic. It inserts one bounded checkpoint and returns:

- whether a gate is required
- what evidence obligations apply
- whether current evidence is sufficient
- how to downgrade safely if it is not

## Key invariants

- The base skill is **single-pass**.
- The base skill is **stateless**.
- `gate_required = false` is a valid fast exit.
- The canonical input and output templates must stay aligned with the protocol and schema.

If you want multi-step orchestration, build it outside this base skill.

## Package layout

- `SKILL.md`: runtime instructions and trigger surface
- `references/protocol.md`: protocol semantics and operating model
- `references/input-template.md`: canonical explicit input shape
- `references/output-template.md`: canonical output shape
- `references/verdict-schema.json`: machine-checkable output schema
- `agents/openai.yaml`: discoverability metadata

## Validation

After editing this skill, validate these things together:

1. `SKILL.md` still reflects the single-pass stateless model.
2. `protocol.md`, `input-template.md`, `output-template.md`, and `verdict-schema.json` stay aligned.
3. `agents/openai.yaml` still references `$evidence-gate`.

## Evaluation

`eval/` contains a 12-case A/B test pack:

- `cases.jsonl`: test cases covering fast-exit, PASS, SOFT_PASS, BLOCK, CONFLICT
- `rubric.md`: 5-dimension scoring rubric
- `score-template.csv`: results template (includes a completed baseline vs gated run)
