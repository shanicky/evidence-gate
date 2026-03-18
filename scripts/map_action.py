#!/usr/bin/env python3
"""Deterministic action mapper for Decision Assurance."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

VALID_VERDICTS = ("PASS", "SOFT_PASS", "BLOCK", "CONFLICT", "ESCALATE")
VALID_TIERS = ("LOW", "MEDIUM", "HIGH", "CRITICAL")
VALID_ACTIONS = ("allow", "allow_advisory", "require_human", "block", "escalate")

BASE_MAP = {
    "PASS": {
        "LOW": "allow",
        "MEDIUM": "allow",
        "HIGH": "allow",
        "CRITICAL": "allow",
    },
    "SOFT_PASS": {
        "LOW": "allow_advisory",
        "MEDIUM": "allow_advisory",
        "HIGH": "require_human",
        "CRITICAL": "require_human",
    },
    "BLOCK": {
        "LOW": "block",
        "MEDIUM": "block",
        "HIGH": "block",
        "CRITICAL": "block",
    },
    "CONFLICT": {
        "LOW": "allow_advisory",
        "MEDIUM": "allow_advisory",
        "HIGH": "require_human",
        "CRITICAL": "require_human",
    },
    "ESCALATE": {
        "LOW": "escalate",
        "MEDIUM": "escalate",
        "HIGH": "escalate",
        "CRITICAL": "escalate",
    },
}
ACTION_RANK = {
    "allow": 0,
    "allow_advisory": 1,
    "require_human": 2,
    "block": 3,
    "escalate": 4,
}


def resolve_action(
    verdict: str, stakes_tier: str, action_policy_override: dict[str, Any] | None
) -> dict[str, Any]:
    if verdict not in BASE_MAP:
        raise ValueError(f"Unsupported verdict: {verdict}")
    if stakes_tier not in BASE_MAP[verdict]:
        raise ValueError(f"Unsupported stakes_tier: {stakes_tier}")

    base_action = BASE_MAP[verdict][stakes_tier]
    governed_action = base_action
    override_applied = False

    if action_policy_override:
        forced_action = action_policy_override.get("forced_action")
        if forced_action:
            if forced_action not in ACTION_RANK:
                raise ValueError(f"Unsupported forced_action: {forced_action}")
            if ACTION_RANK[forced_action] > ACTION_RANK[governed_action]:
                governed_action = forced_action
                override_applied = True

    return {
        "governed_action": governed_action,
        "rule_id": f"{verdict}:{stakes_tier}",
        "override_applied": override_applied,
    }


def run_tests() -> int:
    failures: list[str] = []
    total = 0
    for verdict in VALID_VERDICTS:
        for tier in VALID_TIERS:
            total += 1
            result = resolve_action(verdict, tier, None)
            expected = BASE_MAP[verdict][tier]
            if result["governed_action"] != expected:
                failures.append(
                    f"{verdict}:{tier}: expected {expected}, got {result['governed_action']}"
                )

    override_cases = [
        ("PASS", "HIGH", {"forced_action": "require_human"}, "require_human", True),
        ("BLOCK", "LOW", {"forced_action": "allow"}, "block", False),
        ("SOFT_PASS", "MEDIUM", {"forced_action": "block"}, "block", True),
    ]
    total += len(override_cases)
    for verdict, tier, override, expected_action, expected_flag in override_cases:
        result = resolve_action(verdict, tier, override)
        if result["governed_action"] != expected_action or result["override_applied"] != expected_flag:
            failures.append(
                f"{verdict}:{tier} override {override} -> expected ({expected_action}, {expected_flag}) got "
                f"({result['governed_action']}, {result['override_applied']})"
            )

    if failures:
        print(json.dumps({"passed": False, "total": total, "failures": failures}, indent=2))
        return 1

    print(json.dumps({"passed": True, "total": total}, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", action="store_true", help="Run action-map tests")
    args = parser.parse_args()

    if args.test:
        return run_tests()

    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(
            json.dumps({"error": f"invalid JSON input: {exc}"}),
            file=sys.stderr,
        )
        return 2

    try:
        result = resolve_action(
            payload.get("verdict"),
            payload.get("stakes_tier"),
            payload.get("action_policy_override"),
        )
    except ValueError as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 2

    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
