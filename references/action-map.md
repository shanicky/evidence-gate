# Decision Assurance Action Map

<!-- This table is duplicated inline in SKILL.md §Action Governor. Keep both in sync. -->

Use this fixed mapping from `(verdict, stakes_tier)` to `governed_action`.

| verdict | LOW | MEDIUM | HIGH | CRITICAL |
| --- | --- | --- | --- | --- |
| PASS | allow | allow | allow | allow |
| SOFT_PASS | allow_advisory | allow_advisory | require_human | require_human |
| BLOCK | block | block | block | block |
| CONFLICT | allow_advisory | allow_advisory | require_human | require_human |
| ESCALATE | escalate | escalate | escalate | escalate |

## Interpretation notes

- `PASS` means the evidence is good enough for the requested strength.
- `SOFT_PASS` means the caller may only continue with weaker framing or bounded
  continuation.
- `BLOCK` is a hard stop for the requested claim or action.
- `CONFLICT` permits only low-tier advisory continuation; high-tier use needs
  human review.
- `ESCALATE` always hands off to a human or specialist owner.

## Rule IDs

Use `VERDICT:TIER` as the canonical rule identifier in `audit_record.rule_id`.

Examples:

- `PASS:MEDIUM`
- `SOFT_PASS:HIGH`
- `ESCALATE:CRITICAL`
