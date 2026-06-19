# Brainstorming skill — scoring rubric (target ≥95/100)

Scope: `.claude/skills/brainstorming/`. Score = mean of 7 dimensions × 10.

| Dimension | Target | Acceptance criterion (verifiable) |
|---|---|---|
| Activation | 9 | `description:` in SKILL.md unchanged from upstream 6.0.3 |
| Discipline | 10 | HARD-GATE contains an explicit **User override** clause (T3) AND approaches are conditional (T4) |
| Structure | 10 | 9-step checklist + dot flow graph present (unchanged) |
| Progressive disclosure | 10 | Companion fallback present in BOTH SKILL.md and visual-companion.md (T6) |
| Pedagogy | 10 | "Right-Sizing the Process" section explains *why* ceremony scales (T2) |
| Integration | 10 | The "only writing-plans next" rule is canonical in exactly ONE prose location (T5) |
| Adaptivity | 9 | Tier section + fast-path-for-complete-input present (T2); override present (T3) |

## Acceptance checks (run from repo root)

- [ ] AC2-tiers:    `grep -q "Right-Sizing the Process" .claude/skills/brainstorming/SKILL.md`
- [ ] AC2-fastpath: `grep -qi "Fast-path for complete input" .claude/skills/brainstorming/SKILL.md`
- [ ] AC3-override: `grep -qi "User override" .claude/skills/brainstorming/SKILL.md`
- [ ] AC4-cond:     `grep -qi "genuinely competitive" .claude/skills/brainstorming/SKILL.md`
- [ ] AC4-noabs:    `! grep -q "Always propose 2-3 approaches before settling" .claude/skills/brainstorming/SKILL.md`
- [ ] AC5-dedup:    `[ "$(grep -c "The terminal state is invoking writing-plans" .claude/skills/brainstorming/SKILL.md)" = "0" ]` (standalone redundant line removed)
- [ ] AC6-skillfb:  `grep -qi "fall back to text" .claude/skills/brainstorming/SKILL.md`
- [ ] AC6-vcfb:     `grep -qi "## Fallback" .claude/skills/brainstorming/visual-companion.md`
- [ ] AC-desc:      description line byte-identical to upstream (manual diff)
- [ ] AC-gate:      HARD-GATE still requires design + approval before implementation (manual read)
