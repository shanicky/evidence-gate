#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASES_FILE="$ROOT_DIR/eval/cases.jsonl"
JUDGE_PROTOCOL_FILE="$ROOT_DIR/references/judge-protocol.md"
JUDGE_OUTPUT_TEMPLATE_FILE="$ROOT_DIR/references/judge-output-template.md"
VALIDATE_SCRIPT="$ROOT_DIR/scripts/validate.py"
OUTPUT_CSV="${OUTPUT_CSV:-$ROOT_DIR/eval/score-template.csv}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/.context/eval-results/$(date +%Y%m%d-%H%M%S)}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-}"
ANTHROPIC_API_BASE="${ANTHROPIC_API_BASE:-https://api.anthropic.com}"
ANTHROPIC_MAX_TOKENS="${ANTHROPIC_MAX_TOKENS:-4000}"
CASE_IDS="${CASE_IDS:-}"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ANTHROPIC_API_KEY is required." >&2
  exit 1
fi

if [[ -z "$ANTHROPIC_MODEL" ]]; then
  echo "ANTHROPIC_MODEL is required." >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

python3 - "$CASES_FILE" "$JUDGE_PROTOCOL_FILE" "$JUDGE_OUTPUT_TEMPLATE_FILE" "$OUTPUT_CSV" "$RESULTS_DIR" "$VALIDATE_SCRIPT" "$ANTHROPIC_API_KEY" "$ANTHROPIC_MODEL" "$ANTHROPIC_API_BASE" "$ANTHROPIC_MAX_TOKENS" "$CASE_IDS" <<'PY'
import csv
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

cases_path = Path(sys.argv[1])
judge_protocol_path = Path(sys.argv[2])
judge_output_template_path = Path(sys.argv[3])
output_csv_path = Path(sys.argv[4])
results_dir = Path(sys.argv[5])
validate_script_path = Path(sys.argv[6])
api_key = sys.argv[7]
model = sys.argv[8]
api_base = sys.argv[9].rstrip("/")
max_tokens = int(sys.argv[10])
case_filter_raw = sys.argv[11]
case_filter = {item.strip() for item in case_filter_raw.split(",") if item.strip()}
sys.path.insert(0, str(validate_script_path.parent))

from classify_tier import classify_tier  # noqa: E402
from map_action import resolve_action  # noqa: E402

prompts_dir = results_dir / "prompts"
responses_dir = results_dir / "responses"
prompts_dir.mkdir(parents=True, exist_ok=True)
responses_dir.mkdir(parents=True, exist_ok=True)

judge_protocol_text = judge_protocol_path.read_text()
judge_output_template_text = judge_output_template_path.read_text()
judge_system_prompt = (
    judge_protocol_text.strip()
    + "\n\n"
    + judge_output_template_text.strip()
    + "\n\n"
    + "You are the Calibrated Judge in a Decision Assurance pipeline.\n"
    + "The stakes tier has been pre-computed by scripts/classify_tier.py.\n"
    + "Return ONLY the judgment JSON object as defined in the output template.\n"
    + "Do NOT return stakes or action objects. The runtime assembles the full pipeline envelope.\n"
    + "Use the provided stakes_tier exactly. Do not re-classify the case.\n"
    + "Return valid JSON only."
)
cases = [json.loads(line) for line in cases_path.read_text().splitlines() if line.strip()]
if case_filter:
    cases = [case for case in cases if case["id"] in case_filter]

with output_csv_path.open(newline="") as handle:
    rows = list(csv.DictReader(handle))
fieldnames = rows[0].keys() if rows else []
row_index = {(row["case_id"], row["setup"]): row for row in rows}


def call_anthropic(system_prompt, user_prompt):
    body = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": user_prompt}],
    }
    if system_prompt:
        body["system"] = system_prompt
    request = urllib.request.Request(
        f"{api_base}/v1/messages",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "content-type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace").strip()
        raise RuntimeError(
            f"Anthropic API HTTP {exc.code}: {error_body or exc.reason}"
        ) from exc
    text_parts = []
    for block in payload.get("content", []):
        if block.get("type") == "text":
            text_parts.append(block.get("text", ""))
    return "".join(text_parts).strip()


def extract_json(text):
    candidates = [text.strip()]
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if len(lines) >= 3:
            candidates.append("\n".join(lines[1:-1]).strip())
    start = stripped.find("{")
    end = stripped.rfind("}")
    if start != -1 and end != -1 and end > start:
        candidates.append(stripped[start : end + 1])
    for candidate in candidates:
        if not candidate:
            continue
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    raise ValueError("No valid JSON object found in model output")


def bool_str(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value).lower()


def run_validation(pipeline_output):
    completed = subprocess.run(
        [sys.executable, str(validate_script_path)],
        input=json.dumps(pipeline_output, ensure_ascii=False).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    stdout = completed.stdout.decode("utf-8", errors="replace").strip()
    stderr = completed.stderr.decode("utf-8", errors="replace").strip()
    payload = None
    if stdout:
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError:
            payload = {"valid": False, "violations": [f"validator returned non-JSON: {stdout}"]}
    else:
        payload = {"valid": False, "violations": ["validator returned empty output"]}
    if stderr:
        payload.setdefault("violations", []).append(f"validator stderr: {stderr}")
    payload["exit_code"] = completed.returncode
    return payload


def compute_routing_decision(case, tier):
    known_evidence = case.get("known_evidence") or []
    if tier == "LOW" and not known_evidence:
        return "fast_exit"
    return "assure"


def build_stakes(precomputed, routing_decision):
    tier = precomputed["stakes_tier"]
    applied_rules = precomputed.get("applied_rules") or []
    routing_signals = [f"runtime-assisted tier={tier}"]
    routing_signals.extend(applied_rules)
    tier_rationale = (
        "Runtime-assisted tier from scripts/classify_tier.py: "
        + "; ".join(applied_rules)
        if applied_rules
        else "Runtime-assisted tier from scripts/classify_tier.py."
    )
    return {
        "stakes_tier": tier,
        "routing_decision": routing_decision,
        "tier_rationale": tier_rationale,
        "routing_signals": routing_signals,
    }


def normalize_fast_exit(parsed, case, precomputed):
    tier = precomputed["stakes_tier"]
    stakes = parsed.setdefault("stakes", {})
    judgment = parsed.setdefault("judgment", {})
    action = parsed.setdefault("action", {})

    stakes.update(build_stakes(precomputed, "fast_exit"))
    if "runtime-assisted fast_exit" not in stakes["routing_signals"]:
        stakes["routing_signals"].append("runtime-assisted fast_exit")

    judgment["gate_required"] = False
    judgment["gate_reason"] = (
        "Fast exit: LOW tier with no structured evidence items to evaluate."
    )
    judgment.setdefault("candidate_summary", f"Claim: {case['claim']}")
    judgment["stakes_tier"] = tier
    judgment["requirements"] = []
    judgment["missing_evidence"] = []
    judgment["conflicting_evidence"] = []
    judgment.setdefault(
        "sufficiency_rule",
        "Fast exit: no structured evidence gate is required for this case.",
    )
    judgment["source_independence"] = {
        "rating": "not_applicable",
        "rationale": "Fast exit path. No evidence evaluation was required.",
    }
    judgment["confidence_calibration"] = {
        "level": "not_applicable",
        "rationale": "Fast exit path. No calibration pass was required.",
    }
    judgment["residual_risk"] = {
        "description": "No meaningful residual risk recorded for this fast-exit case.",
        "severity": "none",
        "mitigations": [],
    }
    judgment["verdict"] = "PASS"
    judgment.setdefault("allowed_next_actions", [case["claim"]])
    judgment.setdefault("blocked_next_actions", [])
    judgment.setdefault("fallback_behavior", "Not required. Proceed directly.")
    judgment.setdefault("suggested_wording", case["claim"])
    judgment["next_evidence_actions"] = []

    action_result = resolve_action("PASS", tier, case.get("action_policy_override"))
    action["governed_action"] = action_result["governed_action"]
    action["audit_record"] = {
        "rule_id": action_result["rule_id"],
        "policy_source": "references/action-map.md",
        "decision_basis": "Runtime-assisted fast exit: PASS at LOW maps to allow.",
        "verdict": "PASS",
        "stakes_tier": tier,
        "required_followups": [],
    }
    action.setdefault(
        "caller_instructions",
        "Proceed directly. No evidence gate is required for this low-risk case.",
    )
    for stale_key in [
        "rule_id",
        "verdict",
        "stakes_tier",
        "verdict_input",
        "stakes_tier_input",
        "policy_source",
        "mapping_rationale",
        "follow_ups",
        "advisory_notes",
    ]:
        action.pop(stale_key, None)

    return parsed


def extract_judgment_object(parsed):
    if not isinstance(parsed, dict):
        raise ValueError("Model output must be a JSON object")
    if isinstance(parsed.get("judgment"), dict):
        return dict(parsed["judgment"])
    return dict(parsed)


def assemble_pipeline(judgment, case, precomputed):
    precomputed_tier = precomputed["stakes_tier"]
    routing_decision = compute_routing_decision(case, precomputed_tier)
    if routing_decision == "fast_exit":
        return normalize_fast_exit({}, case, precomputed)

    judgment["stakes_tier"] = precomputed_tier
    judgment["gate_required"] = True
    model_verdict = judgment.get("verdict")
    if model_verdict is None:
        raise ValueError("Model output is missing verdict")

    action_result = resolve_action(
        model_verdict,
        precomputed_tier,
        case.get("action_policy_override"),
    )
    followups = judgment.get("next_evidence_actions")
    if not isinstance(followups, list):
        followups = []

    decision_basis = (
        f"Runtime-assisted mapping: {model_verdict} at {precomputed_tier} maps to "
        f"{action_result['governed_action']} via scripts/map_action.py."
    )
    if action_result.get("override_applied"):
        decision_basis += " A stricter caller override was applied."

    return {
        "stakes": build_stakes(precomputed, "assure"),
        "judgment": judgment,
        "action": {
            "governed_action": action_result["governed_action"],
            "audit_record": {
                "rule_id": action_result["rule_id"],
                "policy_source": "references/action-map.md",
                "decision_basis": decision_basis,
                "verdict": model_verdict,
                "stakes_tier": precomputed_tier,
                "required_followups": followups,
            },
            "caller_instructions": judgment.get("fallback_behavior", ""),
        },
    }


def auto_scores(case, pipeline_output, validation_result):
    judgment = pipeline_output["judgment"]
    action = pipeline_output["action"]
    stakes = pipeline_output["stakes"]

    mismatches = []

    expected_gate = bool_str(case["expected_gate_required"])
    actual_gate = bool_str(judgment["gate_required"])
    if actual_gate != expected_gate:
        mismatches.append(f"gate_required expected {expected_gate} got {actual_gate}")

    if stakes["stakes_tier"] != case["expected_stakes_tier"]:
        mismatches.append(
            f"stakes_tier expected {case['expected_stakes_tier']} got {stakes['stakes_tier']}"
        )
    if stakes["routing_decision"] != case["expected_routing_decision"]:
        mismatches.append(
            "routing_decision expected "
            f"{case['expected_routing_decision']} got {stakes['routing_decision']}"
        )
    if judgment["verdict"] != case["expected_verdict"]:
        mismatches.append(
            f"verdict expected {case['expected_verdict']} got {judgment['verdict']}"
        )
    if action["governed_action"] != case["expected_action"]:
        mismatches.append(
            "governed_action expected "
            f"{case['expected_action']} got {action['governed_action']}"
        )

    fast_exit_shape_ok = True
    if expected_gate == "false":
        fast_exit_shape_ok = (
            stakes["routing_decision"] == "fast_exit"
            and judgment["verdict"] == "PASS"
            and judgment["requirements"] == []
            and judgment["missing_evidence"] == []
            and judgment["conflicting_evidence"] == []
            and judgment["residual_risk"]["severity"] == "none"
            and judgment["residual_risk"]["mitigations"] == []
        )
        if not fast_exit_shape_ok:
            mismatches.append("fast-exit shape invalid")

    trigger_quality = "2" if (
        stakes["routing_decision"] == case["expected_routing_decision"]
        and actual_gate == expected_gate
        and (expected_gate != "false" or fast_exit_shape_ok)
    ) else "0"
    stakes_routing_quality = "2" if (
        stakes["routing_decision"] == case["expected_routing_decision"]
        and stakes["stakes_tier"] == case["expected_stakes_tier"]
    ) else "0"
    verdict_quality = "2" if judgment["verdict"] == case["expected_verdict"] else "0"
    action_quality = "2" if action["governed_action"] == case["expected_action"] else "0"
    validation_pass = "true" if validation_result.get("valid") else "false"
    invariant_robustness = "2" if validation_pass == "true" else "0"

    return {
        "stakes_tier": stakes["stakes_tier"],
        "routing_decision": stakes["routing_decision"],
        "gate_required": actual_gate,
        "verdict": judgment["verdict"],
        "governed_action": action["governed_action"],
        "validation_pass": validation_pass,
        "trigger_quality": trigger_quality,
        "stakes_routing_quality": stakes_routing_quality,
        "verdict_quality": verdict_quality,
        "action_governance_quality": action_quality,
        "invariant_robustness": invariant_robustness,
        "mismatches": mismatches,
    }


for case in cases:
    case_id = case["id"]
    precomputed = classify_tier(
        {
            "impact_profile": case.get("impact_profile"),
            "stakes_override": case.get("stakes_override"),
        }
    )
    precomputed_tier = precomputed["stakes_tier"]
    baseline_prompt = (
        "Answer this case directly without using Decision Assurance.\n\n"
        f"Claim: {case['claim']}\n"
        f"Working context: {case['working_context']}\n"
        f"Execution mode: {case['execution_mode']}\n"
        f"Impact profile: {json.dumps(case.get('impact_profile'), ensure_ascii=False)}\n"
        f"Stakes override: {json.dumps(case.get('stakes_override'), ensure_ascii=False)}\n"
        f"Action policy override: {json.dumps(case.get('action_policy_override'), ensure_ascii=False)}\n"
        f"Known evidence: {json.dumps(case['known_evidence'], ensure_ascii=False)}\n"
    )
    judge_input = {}
    for key in [
        "claim",
        "claim_type",
        "domain",
        "working_context",
        "execution_mode",
        "target_strength",
        "known_evidence",
        "alternatives_checked",
        "available_tools",
        "policy_overrides",
    ]:
        if key in case:
            judge_input[key] = case[key]
    judge_input["stakes_tier"] = precomputed_tier
    skill_user_prompt = (
        "Evaluate this case as the Calibrated Judge in Decision Assurance.\n"
        "Return only the judgment JSON object and no surrounding prose.\n\n"
        f"{json.dumps(judge_input, ensure_ascii=False, indent=2)}"
    )

    (prompts_dir / f"{case_id}.baseline.txt").write_text(baseline_prompt)
    (prompts_dir / f"{case_id}.skill.txt").write_text(skill_user_prompt)

    baseline_row = row_index.get((case_id, "baseline"))
    try:
        baseline_response = call_anthropic(
            "Answer the user's case directly in natural language. Do not use Decision Assurance.",
            baseline_prompt,
        )
        (responses_dir / f"{case_id}.baseline.txt").write_text(baseline_response)
        if baseline_row is not None:
            baseline_row["notes"] = f"Raw response: {responses_dir / f'{case_id}.baseline.txt'}"
    except Exception as exc:  # noqa: BLE001
        if baseline_row is not None:
            baseline_row["notes"] = f"baseline API call failed: {exc}"

    skill_row = row_index.get((case_id, "with_decision_assurance"))
    if skill_row is None:
        continue

    if compute_routing_decision(case, precomputed_tier) == "fast_exit":
        synthetic_response = "Runtime fast exit: judge call skipped."
        (responses_dir / f"{case_id}.skill.txt").write_text(synthetic_response)
        notes = [
            f"Raw response: {responses_dir / f'{case_id}.skill.txt'}",
            "skill call skipped: runtime fast_exit",
        ]
        try:
            parsed = assemble_pipeline({}, case, precomputed)
            (responses_dir / f"{case_id}.skill.json").write_text(
                json.dumps(parsed, indent=2, ensure_ascii=False)
            )
            validation = run_validation(parsed)
            scored = auto_scores(case, parsed, validation)
            for key in [
                "stakes_tier",
                "routing_decision",
                "gate_required",
                "verdict",
                "governed_action",
                "validation_pass",
                "trigger_quality",
                "stakes_routing_quality",
                "verdict_quality",
                "action_governance_quality",
                "invariant_robustness",
            ]:
                skill_row[key] = scored[key]
            if scored["mismatches"]:
                notes.extend(scored["mismatches"])
            if not validation.get("valid"):
                notes.extend(validation.get("violations", []))
        except Exception as exc:  # noqa: BLE001
            skill_row["validation_pass"] = "false"
            skill_row["invariant_robustness"] = "0"
            notes.append(f"pipeline assembly failed: {exc}")
        skill_row["notes"] = " | ".join(notes)
        continue

    try:
        skill_response = call_anthropic(judge_system_prompt, skill_user_prompt)
        (responses_dir / f"{case_id}.skill.txt").write_text(skill_response)
    except Exception as exc:  # noqa: BLE001
        skill_row["notes"] = f"skill API call failed: {exc}"
        continue

    notes = [f"Raw response: {responses_dir / f'{case_id}.skill.txt'}"]
    try:
        parsed = extract_json(skill_response)
        judgment = extract_judgment_object(parsed)
        parsed = assemble_pipeline(judgment, case, precomputed)
        (responses_dir / f"{case_id}.skill.json").write_text(
            json.dumps(parsed, indent=2, ensure_ascii=False)
        )
        validation = run_validation(parsed)
        scored = auto_scores(case, parsed, validation)
        for key in [
            "stakes_tier",
            "routing_decision",
            "gate_required",
            "verdict",
            "governed_action",
            "validation_pass",
            "trigger_quality",
            "stakes_routing_quality",
            "verdict_quality",
            "action_governance_quality",
            "invariant_robustness",
        ]:
            skill_row[key] = scored[key]
        if scored["mismatches"]:
            notes.extend(scored["mismatches"])
        if not validation.get("valid"):
            notes.extend(validation.get("violations", []))
    except Exception as exc:  # noqa: BLE001
        skill_row["validation_pass"] = "false"
        skill_row["invariant_robustness"] = "0"
        notes.append(f"skill JSON parse failed: {exc}")

    skill_row["notes"] = " | ".join(notes)

with output_csv_path.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print(f"Wrote results to {output_csv_path}")
print(f"Raw prompts and responses saved under {results_dir}")
if case_filter:
    print(f"Filtered case_ids: {','.join(sorted(case_filter))}")
PY
