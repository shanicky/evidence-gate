#!/usr/bin/env python3
"""Deterministic stakes-tier classifier for Decision Assurance."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

TIERS = ("LOW", "MEDIUM", "HIGH", "CRITICAL")
TIER_RANK = {tier: index for index, tier in enumerate(TIERS)}
ROOT_OF_TRUST_TOKENS = (
    "signing",
    "artifact-verifier",
    "artifact verifier",
    "root-ca",
    "root ca",
    "certificate-authority",
    "certificate authority",
    "kms",
    "hsm",
)


def normalize_profile(payload: dict[str, Any]) -> dict[str, Any]:
    impact_profile = payload.get("impact_profile") or {}
    affected_assets = impact_profile.get("affected_assets") or []
    if not isinstance(affected_assets, list):
        affected_assets = [affected_assets]
    return {
        "scope": impact_profile.get("scope") or payload.get("impact_scope"),
        "reversibility": impact_profile.get("reversibility")
        or payload.get("reversibility"),
        "blast_radius": impact_profile.get("blast_radius"),
        "time_sensitivity": impact_profile.get("time_sensitivity"),
        "affected_assets": [str(asset) for asset in affected_assets],
    }


def max_tier(left: str, right: str) -> str:
    return left if TIER_RANK[left] >= TIER_RANK[right] else right


def min_tier(left: str, right: str) -> str:
    return left if TIER_RANK[left] <= TIER_RANK[right] else right


def looks_like_root_of_trust(profile: dict[str, Any]) -> bool:
    assets = " ".join(profile.get("affected_assets") or []).lower()
    return any(token in assets for token in ROOT_OF_TRUST_TOKENS)


def classify_tier(payload: dict[str, Any]) -> dict[str, Any]:
    profile = normalize_profile(payload)
    scope = profile["scope"]
    reversibility = profile["reversibility"]
    blast_radius = profile["blast_radius"]
    override = payload.get("stakes_override")
    applied_rules: list[str] = []

    if (
        scope in {"local", "team"}
        and blast_radius == "isolated"
        and reversibility in {"easy", "moderate"}
    ):
        computed = "LOW"
        applied_rules.append(
            "bounded_shortcut: local_or_team + isolated + easy_or_moderate -> LOW"
        )
    else:
        computed = "LOW"
        if (
            scope in {"production", "external"}
            and blast_radius in {"multi_service", "org_wide"}
            and looks_like_root_of_trust(profile)
        ):
            computed = "CRITICAL"
            applied_rules.append(
                "root_of_trust_assets: production_or_external + shared_blast_radius -> CRITICAL"
            )
        elif (
            scope == "external"
            or reversibility == "irreversible"
            or blast_radius == "org_wide"
        ):
            computed = "CRITICAL"
            applied_rules.append(
                "precedence: external_or_irreversible_or_org_wide -> CRITICAL"
            )
        elif (
            scope == "production"
            or reversibility == "hard"
            or blast_radius == "multi_service"
        ):
            computed = "HIGH"
            applied_rules.append(
                "precedence: production_or_hard_or_multi_service -> HIGH"
            )
        elif (
            scope == "service"
            or blast_radius == "single_service"
            or reversibility == "moderate"
        ):
            computed = "MEDIUM"
            applied_rules.append(
                "precedence: service_or_single_service_or_moderate -> MEDIUM"
            )
        else:
            applied_rules.append("default: no higher-impact signal matched -> LOW")

    if override in TIER_RANK and TIER_RANK[override] > TIER_RANK[computed]:
        computed = override
        applied_rules.append(f"override_floor: stakes_override raised tier to {override}")

    ceiling = None
    if blast_radius in {"isolated", "team"} and scope in {"service", "team"}:
        ceiling = "MEDIUM"
        applied_rules.append(
            "ceiling: isolated_or_team blast radius + service_or_team scope -> MEDIUM"
        )
        if reversibility in {"easy", "moderate"}:
            ceiling = "LOW"
            applied_rules.append(
                "ceiling: easy_or_moderate reversibility under bounded shared scope -> LOW"
            )
    elif blast_radius == "single_service":
        ceiling = "HIGH"
        applied_rules.append("ceiling: single_service blast radius -> HIGH")

    final_tier = min_tier(computed, ceiling) if ceiling else computed
    if ceiling and final_tier != computed:
        applied_rules.append(f"final: min({computed}, {ceiling}) -> {final_tier}")
    else:
        applied_rules.append(f"final: {final_tier}")

    return {"stakes_tier": final_tier, "applied_rules": applied_rules}


def run_tests() -> int:
    cases_path = Path(__file__).resolve().parents[1] / "eval" / "cases.jsonl"
    failures: list[str] = []
    total = 0
    for raw_line in cases_path.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        case = json.loads(raw_line)
        total += 1
        payload = {
            "impact_profile": case.get("impact_profile"),
            "stakes_override": case.get("stakes_override"),
        }
        result = classify_tier(payload)
        expected = case["expected_stakes_tier"]
        if result["stakes_tier"] != expected:
            failures.append(
                f"{case['id']}: expected {expected}, got {result['stakes_tier']}"
            )

    if failures:
        print(json.dumps({"passed": False, "total": total, "failures": failures}, indent=2))
        return 1

    print(json.dumps({"passed": True, "total": total}, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", action="store_true", help="Run tier-classifier tests")
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

    print(json.dumps(classify_tier(payload), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
