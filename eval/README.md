# Evidence Gate Eval Pack

This folder contains a small evaluation pack for checking whether `evidence-gate` is actually useful in practice.

## Files

- `cases.jsonl`: test cases covering fast-exit, `PASS`, `SOFT_PASS`, `BLOCK`, and `CONFLICT`
- `rubric.md`: scoring rules
- `score-template.csv`: a simple A/B comparison sheet

## Recommended workflow

1. Run each case with the baseline agent.
2. Run the same case with `evidence-gate`.
3. Score both runs with `rubric.md`.
4. Compare total score, verdict quality, downgrade quality, and false-positive gating.

## What this pack is trying to prove

The skill is useful if it:

- reduces unsupported strong conclusions
- reduces unsafe high-impact recommendations
- improves safe downgrade behavior
- does not create too much noise on low-risk tasks

## Notes

- The pack is intentionally small and manual-first.
- Expand it only if the new cases add a genuinely different failure mode.
- Keep the labels and expected verdicts stable so results remain comparable over time.
