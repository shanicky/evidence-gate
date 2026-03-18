# Decision Assurance Judge Input Template

When a caller wants deterministic control over the Calibrated Judge, use this
JSON shape:

```json
{
  "claim": "The root cause is a nil dereference in request parsing.",
  "claim_type": "diagnosis",
  "domain": "coding",
  "stakes_tier": "MEDIUM",
  "execution_mode": "advisory",
  "target_strength": "definitive",
  "known_evidence": [
    {
      "id": "ev-1",
      "summary": "A regression test reproduces the crash when request.user is missing.",
      "kind": "test",
      "source": "local test suite",
      "artifact_ref": "tests/auth_test.rb:42",
      "reliability": "high",
      "timestamp": "2026-03-18T09:15:00Z",
      "environment": "local",
      "freshness": "current",
      "independence_group": "local-test-suite",
      "supports": ["req-repro"],
      "contradicts": []
    }
  ],
  "alternatives_checked": [
    "The crash is caused by a malformed request body instead of a nil user object."
  ],
  "available_tools": ["rg", "tests", "logs"],
  "policy_overrides": []
}
```

## Rules

- `claim` is the only required field for a minimal invocation.
- Provide `stakes_tier` explicitly when the judge is called inside the full
  pipeline.
- Keep `known_evidence` explicit and artifact-linked.
- Provenance fields such as `timestamp`, `environment`, `freshness`, and
  `independence_group` are optional, but strongly preferred for consequential
  cases.
- Keep `alternatives_checked` concise and concrete.
- Use `policy_overrides` only for stricter local policy, not for hidden
  reasoning.
