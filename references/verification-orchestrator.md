# Decision Assurance Verification Orchestrator

Use this protocol for an external orchestrator that collects evidence across
multiple rounds and re-invokes the base skill with enriched input.

The orchestrator is not part of the base skill runtime.
It sits outside the base skill and owns the verification loop explicitly.

## Goal

The orchestrator answers:

**When the base skill returns missing or conflicting evidence, how should an
outer workflow collect more evidence, retry safely, and stop deterministically?**

## Relationship to the base skill

The base skill remains:

- single-pass
- stateless
- non-orchestrating

The orchestrator is where multi-round collection belongs.
Every retry must pass the newly collected evidence back into a fresh
`decision-assurance` invocation.

## Control loop

Use this loop unless a stricter caller policy exists:

1. Invoke `decision-assurance` with the current input.
2. If the verdict is `PASS` or `ESCALATE`, stop.
3. If the verdict is `SOFT_PASS`, `BLOCK`, or `CONFLICT`:
   - read `next_evidence_actions`
   - select collectors for missing or conflicting requirements only
   - dispatch collectors
   - merge collected evidence into `known_evidence`
   - re-invoke `decision-assurance`
4. Stop when:
   - the verdict becomes `PASS`
   - the verdict becomes `ESCALATE`
   - `max_rounds` is reached
   - all candidate collectors fail or remain pending
5. If the loop stops without `PASS`, escalate or report the best current state.

## Orchestrator input

Recommended orchestrator input:

```json
{
  "initial_pipeline_input": {},
  "max_rounds": 3,
  "collector_registry": [
    "test-runner",
    "log-query",
    "human-review"
  ]
}
```

### Required behavior

- `max_rounds` defaults to `3`
- never dispatch collectors for already satisfied requirements
- do not repeat a collector that already succeeded for the same requirement
- do allow retries for `pending` or `partial` collectors when outer policy
  permits
- preserve provenance and collector status when merging evidence

## Collector selection

Each collector should target one or more `missing` or `conflicting`
requirements.

Recommended selection strategy:

- `req-isolation` -> `controlled_test`
- `req-impact` -> `observational_query`
- `req-approval` -> `human_report`
- `req-policy` -> `search_retrieval` or `human_report`

Use collector types from `collector-interface.md`.

## Merge rules

When collector output arrives:

- merge `success` evidence into `known_evidence`
- merge `partial` evidence into `known_evidence` and preserve the collector
  status in outer orchestration logs
- do not merge `pending` outputs as evidence
- do not drop failed collector attempts from the audit trail

Collected evidence must reuse the evidence item shape from
`judge-protocol.md`, including provenance fields such as:

- `timestamp`
- `environment`
- `freshness`
- `independence_group`

## Auto-escalate rules

Automatically escalate when any of these are true:

- `max_rounds` is exceeded
- all remaining collectors failed
- the only remaining blockers are pending human approvals beyond the loop
  budget
- the enriched evidence still leaves the workflow in `CONFLICT` after the final
  round

Do not auto-escalate earlier than needed if a deterministic collector can still
materially change the verdict.

## Output

Validate orchestrator output with `orchestrator-schema.json`.

Canonical shape:

```json
{
  "final_verdict": "PASS",
  "rounds": 2,
  "collection_log": [
    {
      "round": 1,
      "collectors_dispatched": ["test-runner"],
      "evidence_collected": ["ev-collected-1"],
      "intermediate_verdict": "SOFT_PASS"
    },
    {
      "round": 2,
      "collectors_dispatched": ["human-review"],
      "evidence_collected": ["ev-collected-2"],
      "intermediate_verdict": "PASS"
    }
  ],
  "final_pipeline_output": {}
}
```

## Termination semantics

- `final_verdict = PASS`
  - the loop gathered enough evidence
- `final_verdict = ESCALATE`
  - the loop hit a hard stop or domain handoff
- `final_verdict = SOFT_PASS`, `BLOCK`, or `CONFLICT`
  - allowed only when the caller deliberately stops early and reports the final
    pipeline output without further automation

## Safety constraints

These are mandatory:

- keep a hard round limit
- keep collector dispatch targeted to unsatisfied requirements
- preserve collector provenance and status
- never claim the orchestrator made the base skill stateful

## Related files

- `collector-interface.md`
- `orchestrator-schema.json`
- `judge-protocol.md`
