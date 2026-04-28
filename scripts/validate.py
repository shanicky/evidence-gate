#!/usr/bin/env python3
"""Invariant validator for Decision Assurance pipeline outputs."""

from __future__ import annotations

import json
import re
import sys
from typing import Any

from map_action import resolve_action

RULE_ID_PATTERN = re.compile(r"^(PASS|SOFT_PASS|BLOCK|CONFLICT|ESCALATE):(LOW|MEDIUM|HIGH|CRITICAL)$")
EXPECTED_ACTION_KEYS = {"governed_action", "audit_record", "caller_instructions"}
LEGACY_ACTION_KEYS = {
    "rule_id",
    "verdict",
    "stakes_tier",
    "verdict_input",
    "stakes_tier_input",
    "policy_source",
    "mapping_rationale",
    "follow_ups",
    "advisory_notes",
}


def get_nested(mapping: dict[str, Any], *keys: str) -> Any:
    current: Any = mapping
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current

def validate_pipeline(payload: dict[str, Any]) -> list[str]:
    violations: list[str] = []
    stakes = payload.get("stakes")
    judgment = payload.get("judgment")
    action = payload.get("action")
    if not isinstance(stakes, dict):
        stakes = {}
    if not isinstance(judgment, dict):
        judgment = {}
    if not isinstance(action, dict):
        action = {}

    stakes_tier = stakes.get("stakes_tier")
    routing_decision = stakes.get("routing_decision")
    verdict = judgment.get("verdict")
    gate_required = judgment.get("gate_required")
    governed_action = action.get("governed_action")
    action_keys = set(action)
    audit_record = action.get("audit_record")
    if not isinstance(audit_record, dict):
        violations.append("action.audit_record must be an object")
        audit_record = {}
    missing_action_keys = sorted(EXPECTED_ACTION_KEYS - action_keys)
    extra_action_keys = sorted(action_keys - EXPECTED_ACTION_KEYS)
    legacy_action_keys = sorted(LEGACY_ACTION_KEYS & action_keys)
    if missing_action_keys:
        violations.append(
            "action is missing required top-level keys: "
            + ", ".join(missing_action_keys)
        )
    if extra_action_keys:
        violations.append(
            "action has unsupported top-level keys: "
            + ", ".join(extra_action_keys)
        )
    if legacy_action_keys:
        violations.append(
            "action must not use legacy top-level audit fields: "
            + ", ".join(legacy_action_keys)
        )

    action_verdict = audit_record.get("verdict")
    action_tier = audit_record.get("stakes_tier")
    rule_id = audit_record.get("rule_id")
    policy_source = audit_record.get("policy_source")

    if routing_decision == "fast_exit":
        if stakes_tier != "LOW":
            violations.append("fast_exit requires stakes.stakes_tier = LOW")
        if gate_required is not False:
            violations.append("fast_exit requires judgment.gate_required = false")
        if verdict != "PASS":
            violations.append("fast_exit requires judgment.verdict = PASS")
        if judgment.get("requirements") != []:
            violations.append("fast_exit requires judgment.requirements = []")
        if judgment.get("missing_evidence") != []:
            violations.append("fast_exit requires judgment.missing_evidence = []")
        if judgment.get("conflicting_evidence") != []:
            violations.append("fast_exit requires judgment.conflicting_evidence = []")
        if get_nested(judgment, "source_independence", "rating") != "not_applicable":
            violations.append(
                "fast_exit requires judgment.source_independence.rating = not_applicable"
            )
        if get_nested(judgment, "confidence_calibration", "level") != "not_applicable":
            violations.append(
                "fast_exit requires judgment.confidence_calibration.level = not_applicable"
            )
        if get_nested(judgment, "residual_risk", "severity") != "none":
            violations.append("fast_exit requires judgment.residual_risk.severity = none")
        if get_nested(judgment, "residual_risk", "mitigations") != []:
            violations.append("fast_exit requires judgment.residual_risk.mitigations = []")
        if governed_action != "allow":
            violations.append("fast_exit requires action.governed_action = allow")

    if verdict == "ESCALATE":
        if gate_required is not True:
            violations.append("ESCALATE requires judgment.gate_required = true")
        if governed_action != "escalate":
            violations.append("ESCALATE requires action.governed_action = escalate")

    if verdict and verdict != "PASS" and gate_required is not True:
        violations.append("Non-PASS verdicts require judgment.gate_required = true")

    judgment_tier = judgment.get("stakes_tier")
    if stakes_tier != judgment_tier:
        violations.append("stakes.stakes_tier must equal judgment.stakes_tier")
    if action_tier is None:
        violations.append("action audit tier is missing")
    elif stakes_tier != action_tier:
        violations.append("stakes.stakes_tier must equal action audit tier")

    if verdict and stakes_tier and governed_action:
        try:
            expected_action = resolve_action(verdict, stakes_tier, None)["governed_action"]
            if governed_action != expected_action:
                violations.append(
                    "action.governed_action must match scripts/map_action.py for judgment.verdict and stakes.stakes_tier"
                )
        except ValueError as exc:
            violations.append(str(exc))

    if action_verdict is None:
        violations.append("action audit verdict is missing")
    elif verdict != action_verdict:
        violations.append("judgment.verdict must equal action audit verdict")

    if rule_id is None:
        violations.append("action rule_id is missing")
    elif not RULE_ID_PATTERN.match(rule_id):
        violations.append("action rule_id must use VERDICT:TIER format")
    elif verdict and stakes_tier and rule_id != f"{verdict}:{stakes_tier}":
        violations.append("action rule_id must match judgment.verdict and stakes.stakes_tier")

    if policy_source != "references/action-map.md":
        violations.append(
            "action.audit_record.policy_source must equal references/action-map.md"
        )

    return violations


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(
            json.dumps(
                {
                    "valid": False,
                    "violations": [f"invalid JSON input: {exc}"],
                },
                ensure_ascii=False,
            )
        )
        return 2

    if not isinstance(payload, dict):
        print(
            json.dumps(
                {
                    "valid": False,
                    "violations": ["top-level JSON value must be an object"],
                },
                ensure_ascii=False,
            )
        )
        return 2

    violations = validate_pipeline(payload)
    print(json.dumps({"valid": not violations, "violations": violations}, ensure_ascii=False))
    return 0 if not violations else 1


if __name__ == "__main__":
    raise SystemExit(main())
