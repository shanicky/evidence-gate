# Decision Assurance

Decision Assurance is a stateless, single-pass skill for routing a tentative
claim or action through three modules:

1. Stakes Router
2. Calibrated Judge
3. Action Governor

It evolves `evidence-gate` from a single evidence check into a full assurance
pipeline that classifies stakes, judges evidence sufficiency, and maps the
result to a governed action.

## Purpose

Use this skill when an agent is about to:

- present a strong diagnosis as settled
- make a safety assertion
- recommend or execute a high-impact action
- approve or deny a consequential request

The pipeline returns:

- `stakes`: tier and routing decision
- `judgment`: structured evidence assessment
- `action`: deterministic governance outcome

## Key invariants

- The base skill is **single-pass**.
- The base skill is **stateless**.
- Fast exit is preserved through the full pipeline envelope.
- The action map is deterministic.
- Module contracts must stay aligned with their templates and schemas.

## Package layout

- `SKILL.md`: runtime instructions and trigger surface
- `references/stakes-router.md`: router protocol
- `references/stakes-schema.json`: router schema
- `references/judge-*`: evolved evidence gate contract set
- `references/action-*`: governance mapping contract set
- `references/pipeline-*`: top-level input, output, and schema
- `references/spec-compiler.md`: Phase 2 placeholder
- `references/verification-orchestrator.md`: Phase 2 placeholder
- `agents/openai.yaml`: OpenAI discoverability metadata

## Evaluation

`eval/` contains the current Decision Assurance evaluation pack.
The original Evidence Gate pack is archived under `eval/legacy/`.
