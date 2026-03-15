# Evidence Gate

Stateless, single-pass skill. Agents use it to verify whether a strong claim or high-impact action is sufficiently supported by explicit evidence before presenting or executing it.

`CLAUDE.md` is a symlink to this file.

## Project structure

```
SKILL.md                           # Entry point — frontmatter + runtime instructions
references/
  protocol.md                      # Protocol semantics, schemas, evidence evaluation pitfalls
  input-template.md                # Canonical explicit input shape (claim is the only required field)
  output-template.md               # Canonical output shape (gate_required + verdict + requirements)
  verdict-schema.json              # Machine-checkable JSON schema with fast-exit constraint
agents/
  openai.yaml                      # OpenAI agent discoverability metadata
```

Evaluation assets live in `eval/` — keep them separate from the skill package.

## Invariants

1. **Single-pass.** No second gate round, no retry loop, no stateful collection cycle.
2. **Stateless.** No persistent files, no hidden memory, no cross-call state. Multi-step orchestration belongs outside this base skill.
3. **Contracts aligned.** When changing any field shape, update all five together: `SKILL.md`, `protocol.md`, `input-template.md`, `output-template.md`, `verdict-schema.json`.
4. **Fast-exit preserved.** `gate_required = false` → `verdict = PASS` + empty requirements/missing/conflicting. This is enforced in `verdict-schema.json`.
5. **Structured outputs.** Every output keeps the full top-level shape from `output-template.md`. Never silently drop fields.
6. **Evidence evaluation pitfalls enforced.** `protocol.md` contains pitfall rules (temporal correlation ≠ causation, single-source, scope mismatch, absence ≠ evidence). When a pitfall applies, mark the requirement `missing` or `conflicting`, not `satisfied`.

## Validation checklist

After any edit, confirm:

- [ ] `SKILL.md` frontmatter has only `name` and `description`
- [ ] `SKILL.md` body still reflects the single-pass stateless model
- [ ] All five contract files are aligned on field shapes
- [ ] `verdict-schema.json` parses as valid JSON
- [ ] `verdict-schema.json` fast-exit constraint (`gate_required=false` → `PASS` + empty arrays) is present
- [ ] `agents/openai.yaml` parses as valid YAML
