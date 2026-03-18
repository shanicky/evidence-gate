#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASES_FILE="$ROOT_DIR/eval/cases.jsonl"
SKILL_FILE="$ROOT_DIR/SKILL.md"
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

python3 - "$CASES_FILE" "$SKILL_FILE" "$OUTPUT_CSV" "$RESULTS_DIR" "$ANTHROPIC_API_KEY" "$ANTHROPIC_MODEL" "$ANTHROPIC_API_BASE" "$ANTHROPIC_MAX_TOKENS" "$CASE_IDS" <<'PY'
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

cases_path = Path(sys.argv[1])
skill_path = Path(sys.argv[2])
output_csv_path = Path(sys.argv[3])
results_dir = Path(sys.argv[4])
api_key = sys.argv[5]
model = sys.argv[6]
api_base = sys.argv[7].rstrip("/")
max_tokens = int(sys.argv[8])
case_filter_raw = sys.argv[9]
case_filter = {item.strip() for item in case_filter_raw.split(",") if item.strip()}

prompts_dir = results_dir / "prompts"
responses_dir = results_dir / "responses"
prompts_dir.mkdir(parents=True, exist_ok=True)
responses_dir.mkdir(parents=True, exist_ok=True)

skill_prompt = skill_path.read_text()
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


def auto_scores(case, pipeline_output):
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

    return {
        "stakes_tier": stakes["stakes_tier"],
        "routing_decision": stakes["routing_decision"],
        "gate_required": actual_gate,
        "verdict": judgment["verdict"],
        "governed_action": action["governed_action"],
        "trigger_quality": trigger_quality,
        "stakes_routing_quality": stakes_routing_quality,
        "verdict_quality": verdict_quality,
        "action_governance_quality": action_quality,
        "mismatches": mismatches,
    }


for case in cases:
    case_id = case["id"]
    baseline_prompt = (
        "Answer this case directly without using Decision Assurance.\n\n"
        f"Claim: {case['claim']}\n"
        f"Working context: {case['working_context']}\n"
        f"Execution mode: {case['execution_mode']}\n"
        f"Known evidence: {json.dumps(case['known_evidence'], ensure_ascii=False)}\n"
    )
    skill_prompt_input = {
        "claim": case["claim"],
        "working_context": case["working_context"],
        "execution_mode": case["execution_mode"],
        "known_evidence": case["known_evidence"],
        "impact_profile": case.get("impact_profile"),
    }
    skill_user_prompt = (
        "Evaluate this case with Decision Assurance.\n"
        "Return only the final pipeline output JSON and no surrounding prose.\n\n"
        f"{json.dumps(skill_prompt_input, ensure_ascii=False, indent=2)}"
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

    try:
        skill_response = call_anthropic(skill_prompt, skill_user_prompt)
        (responses_dir / f"{case_id}.skill.txt").write_text(skill_response)
    except Exception as exc:  # noqa: BLE001
        skill_row["notes"] = f"skill API call failed: {exc}"
        continue

    notes = [f"Raw response: {responses_dir / f'{case_id}.skill.txt'}"]
    try:
        parsed = extract_json(skill_response)
        (responses_dir / f"{case_id}.skill.json").write_text(
            json.dumps(parsed, indent=2, ensure_ascii=False)
        )
        scored = auto_scores(case, parsed)
        for key in [
            "stakes_tier",
            "routing_decision",
            "gate_required",
            "verdict",
            "governed_action",
            "trigger_quality",
            "stakes_routing_quality",
            "verdict_quality",
            "action_governance_quality",
        ]:
            skill_row[key] = scored[key]
        if scored["mismatches"]:
            notes.extend(scored["mismatches"])
    except Exception as exc:  # noqa: BLE001
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
