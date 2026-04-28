# Decision Assurance Eval Pack

This folder contains a manual-first evaluation pack for the full
`decision-assurance` pipeline.

## Files

- `cases.jsonl`: 40 cases covering all `verdict × stakes_tier` combinations,
  clean fast-exit behavior, one routing-boundary case, and 15 adversarial
  policy-grade cases
- `rubric.md`: 8-dimension scoring rubric
- `score-template.csv`: worksheet for baseline versus Decision Assurance runs
- `run-eval.sh`: Anthropic API runner that executes baseline and skill runs,
  then auto-fills deterministic columns
- `legacy/`: archived v1 Evidence Gate evaluation assets

## Recommended workflow

This runner now uses a runtime-assisted, judge-only pipeline:

1. `scripts/classify_tier.py` pre-computes the stakes tier.
2. The runtime prompts the model only with
   `references/judge-protocol.md` and
   `references/judge-output-template.md`.
3. The model returns only the `judgment` JSON object.
4. The runtime assembles the full pipeline envelope.
5. `scripts/map_action.py` computes the governed action and canonical
   `rule_id`.
6. `scripts/validate.py` runs on the assembled pipeline.

1. Run each case with the baseline agent.
2. Run the same case with `decision-assurance`.
3. Score both runs using `rubric.md`.
4. Compare total score, routing quality, verdict quality, governance quality,
   invariant robustness, and fast-exit noise.

## Runner usage

Set these environment variables first:

- `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL`
- `ANTHROPIC_API_BASE` (optional, defaults to `https://api.anthropic.com`)
- `ANTHROPIC_MAX_TOKENS` (optional, defaults to `4000`)
- `CASE_IDS` (optional, comma-separated subset such as `da-02,da-07`)

Then run:

```bash
./eval/run-eval.sh
```

To rerun only a subset of cases:

```bash
CASE_IDS=da-02,da-07 ./eval/run-eval.sh
```

The runner will:

1. execute a baseline run for each case
2. pre-compute `stakes_tier` with `scripts/classify_tier.py`
3. execute a Decision Assurance judge-only run for each case
4. assemble the full pipeline envelope at runtime
5. post-process `governed_action` and `rule_id` with `scripts/map_action.py`
6. save raw prompts and responses under `.context/eval-results/<timestamp>/`
7. update `eval/score-template.csv` with deterministic fields from the skill
   run, including runtime validation status

The runner auto-fills only what it can check deterministically:

- `stakes_tier`
- `routing_decision`
- `gate_required`
- `verdict`
- `governed_action`
- `validation_pass`
- `trigger_quality`
- `stakes_routing_quality`
- `verdict_quality`
- `action_governance_quality`
- `invariant_robustness`

These columns still need manual review:

- `requirement_quality`
- `downgrade_quality`
- `next_evidence_usefulness`
- `total_score`

## What this pack is trying to prove

Decision Assurance is useful if it:

- routes stakes correctly before making a judgment
- reduces unsupported strong conclusions
- improves downgrade behavior when evidence is incomplete
- maps outcomes to safer governed actions
- keeps low-risk tasks quiet through clean fast exits

## Coverage notes

- Cases `da-01` through `da-20` cover every tier and verdict combination.
- Cases `da-21` through `da-24` are extra fast-exit checks.
- Case `da-25` is a routing-boundary check that should stay in assurance even
  though it superficially looks low risk.
- Cases `da-26` through `da-28` are prompt-injection resilience checks.
- Cases `da-29` through `da-31` stress action-map robustness.
- Cases `da-32` through `da-34` stress tier-boundary and override precedence.
- Cases `da-35` through `da-37` stress provenance and tool-skepticism defects.
- Cases `da-38` through `da-40` stress hidden blast radius and misleading
  framing.
- The original Evidence Gate pack remains unchanged under `legacy/`.
