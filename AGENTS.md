# Decision Assurance

Stateless, single-pass skill. Agents use it to verify whether a consequential
claim or action should fast-exit, proceed with evidence-backed confidence, or
be governed down to advisory, human review, block, or escalation.

`CLAUDE.md` is a symlink to this file.

## Project structure

```text
SKILL.md                              # Entry point — full pipeline instructions
scripts/
  classify_tier.py                    # Deterministic tier classifier
  map_action.py                       # Deterministic verdict/tier action mapper
  validate.py                         # Runtime invariant validator
references/
  stakes-router.md                    # Stakes routing protocol
  stakes-schema.json                  # Stakes output schema
  judge-protocol.md                   # Calibrated Judge protocol
  judge-input-template.md             # Judge input template
  judge-output-template.md            # Judge output template
  judge-verdict-schema.json           # Judge output schema
  action-governor.md                  # Action Governor protocol
  action-map.md                       # Deterministic verdict/tier mapping
  action-output-template.md           # Governor output template
  action-schema.json                  # Governor output schema
  quick-examples.md                   # Worked pipeline outcome examples
  pipeline-input-template.md          # Top-level pipeline input
  pipeline-output-template.md         # Top-level pipeline output
  pipeline-schema.json                # Top-level schema with fast-exit and mapping constraints
  spec-compiler.md                    # Spec Compiler protocol
  spec-compiler-schema.json           # Policy pack schema
  verification-orchestrator.md        # Verification Orchestrator protocol
  collector-interface.md              # Collector request/response contract
  orchestrator-schema.json            # Orchestrator output schema
  examples/
    sre-production.yaml               # Example production SRE policy pack
    research-claims.yaml              # Example research policy pack
agents/
  openai.yaml                         # OpenAI agent discoverability metadata
eval/
  README.md                           # Current evaluation pack guide
  cases.jsonl                         # Decision Assurance cases
  rubric.md                           # 8-dimension scoring rubric
  score-template.csv                  # Evaluation worksheet
  run-eval.sh                         # Anthropic eval runner
  legacy/                             # Archived v1 Evidence Gate eval assets
```

## Invariants

1. **Single-pass.** No second assurance round, no retry loop, no stateful
   collection cycle.
2. **Stateless.** No persistent files, hidden memory, or cross-call state.
   Multi-step orchestration belongs outside this base skill.
3. **Router contract aligned.** When changing stakes fields, update
   `SKILL.md`, `stakes-router.md`, and `stakes-schema.json` together.
4. **Judge contract aligned.** When changing judgment fields, update
   `SKILL.md`, `judge-protocol.md`, `judge-input-template.md`,
   `judge-output-template.md`, and `judge-verdict-schema.json` together.
5. **Governor contract aligned.** When changing governance fields, update
   `SKILL.md`, `action-governor.md`, `action-map.md`,
   `action-output-template.md`, and `action-schema.json` together.
6. **Pipeline contract aligned.** When changing top-level fields, update
   `SKILL.md`, `pipeline-input-template.md`, `pipeline-output-template.md`, and
   `pipeline-schema.json` together.
7. **Fast-exit preserved.** `routing_decision = fast_exit` must imply
   `judgment.gate_required = false`, `judgment.verdict = PASS`, and
   `action.governed_action = allow`.
8. **ESCALATE preserved.** `judgment.verdict = ESCALATE` must imply
   `judgment.gate_required = true` and `action.governed_action = escalate`.
9. **Structured outputs.** Every output keeps the full top-level shape from
   `pipeline-output-template.md`.
10. **Deterministic mapping.** `action-map.md` must cover every
    `verdict × stakes_tier` combination exactly once.

## Validation checklist

After any edit, confirm:

- [ ] `SKILL.md` frontmatter has only `name` and `description`
- [ ] `SKILL.md` still reflects the single-pass stateless model
- [ ] `judge-verdict-schema.json` parses as valid JSON
- [ ] `pipeline-schema.json` parses as valid JSON
- [ ] `spec-compiler-schema.json` parses as valid JSON
- [ ] `orchestrator-schema.json` parses as valid JSON
- [ ] `judge-verdict-schema.json` keeps the fast-exit and `ESCALATE` constraints
- [ ] `pipeline-schema.json` keeps the fast-exit and action-mapping constraints
- [ ] `action-map.md` still covers all verdict and tier combinations
- [ ] `python3 scripts/classify_tier.py --test` passes
- [ ] `python3 scripts/map_action.py --test` passes
- [ ] `scripts/validate.py` accepts a valid pipeline sample
- [ ] example policy pack YAML files parse successfully
- [ ] `agents/openai.yaml` parses as valid YAML
