# Decision Assurance Collector Interface

Use this interface for tools or human workflows that gather evidence between
orchestrator rounds.

Collectors are external to the base skill.
They produce evidence items that the orchestrator can merge back into
`known_evidence`.

## Collector request

```json
{
  "collector_id": "test-runner",
  "collector_type": "controlled_test",
  "input": {
    "target_requirement": "req-isolation",
    "action": "Run canary test for queue isolation"
  }
}
```

### Fields

- `collector_id`: stable identifier for the collector implementation
- `collector_type`: one of the supported collector types
- `input.target_requirement`: the requirement the collector is trying to
  satisfy
- `input.action`: caller-facing description of the requested collection step

## Collector response

```json
{
  "collector_id": "test-runner",
  "collector_type": "controlled_test",
  "output": {
    "status": "success",
    "evidence": {
      "id": "ev-collected-1",
      "summary": "Canary confirmed queue is the outage driver.",
      "kind": "test",
      "source": "production canary",
      "artifact_ref": "runbooks/canary-queue-disable.md",
      "reliability": "high",
      "timestamp": "2026-03-18T10:05:00Z",
      "environment": "production",
      "freshness": "current",
      "independence_group": "canary-control-plane",
      "supports": ["req-isolation"],
      "contradicts": []
    },
    "reason": ""
  }
}
```

### Output status values

- `success`
- `partial`
- `pending`
- `failure`

### Status semantics

- `success`: evidence is ready to merge
- `partial`: some evidence is ready to merge, but collection is incomplete
- `pending`: collector is waiting on an external dependency such as human input
- `failure`: collector did not produce usable evidence

## Supported collector types

- `deterministic_check`
  - examples: linter, type checker, schema validator
- `controlled_test`
  - examples: unit test runner, integration test, canary
- `observational_query`
  - examples: log query, metrics dashboard, trace retrieval
- `search_retrieval`
  - examples: web search, document retrieval, RAG lookup
- `human_report`
  - examples: approval request, expert review, manual analyst response

## Evidence requirements

Collector-produced evidence must reuse the evidence item shape from
`judge-protocol.md`.
That includes provenance fields when available:

- `timestamp`
- `environment`
- `freshness`
- `independence_group`

Do not fabricate provenance.
If a field is unknown, omit it or set `freshness` to `unknown` explicitly.
