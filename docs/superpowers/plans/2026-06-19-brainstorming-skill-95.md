# Brainstorming Skill → 95/100 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork the `superpowers:brainstorming` skill into a project-local override at `.claude/skills/brainstorming/` and raise its quality score from 88/100 to ≥95 by fixing the five weaknesses identified in the evaluation.

**Architecture:** Vendor a complete copy of the upstream skill (v6.0.3) into the repo so it survives plugin updates and is version-controlled, then apply five targeted content edits. Each edit is verified against a committed scoring rubric whose criteria are `grep`-checkable: red against the verbatim copy, green after the edit. The skill is a prose artifact, so "tests" are presence/absence checks on SKILL.md, not a code test framework.

**Tech Stack:** Markdown skill files; Git Bash (grep/cp) on Windows; no build involved (the `verify-gate` Stop hook is a no-op for non-`.java`/`.sql` changes).

## Global Constraints

- British English in all prose (repo `.claude/CLAUDE.md`).
- Conventional Commits; multi-line via heredoc; footer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (repo convention). Confirm the subject line with the user before each commit (repo `.claude/CLAUDE.md`).
- Stage explicit paths only — never `git add -A` (blocked by `block-dangerous.sh`).
- Work on the current feature branch (`docs/claude-config-hardening` or a new `feat/brainstorming-skill` branch) — never commit on `main`/`develop` (blocked by `block-main-commit.sh`).
- The fork's skill `name:` is `brainstorming` (unscoped, project-local) — it does NOT replace `superpowers:brainstorming`; it is a separate, locally-discovered skill.
- **The HARD-GATE's core discipline must be preserved:** a design is presented and approved before any implementation. Edits scale the *ceremony*, never remove the gate.
- DRY / YAGNI: make the minimum edits that move the score; do not rewrite sections that already score well (Structure 10/10, Activation 9/10).
- Preserve the frontmatter `description:` verbatim — it drives skill activation and must not regress.
- Active upstream version is **6.0.3** (per `~/.claude/plugins/cache/claude-plugins-official/superpowers/installed_plugins.json`). If a different version is active, adjust the source path in Task 1.

---

## Target Scoring (how ≥95 is reached)

| Dimension | Before | Target | Lever (task) |
|---|---|---|---|
| Activation / description | 9 | 9 | unchanged (preserve verbatim) |
| Discipline & gating | 9 | 10 | override clause makes the gate principled (T3); conditional alternatives align with YAGNI (T4) |
| Structure (checklist + flow) | 10 | 10 | unchanged |
| Progressive disclosure | 9 | 10 | companion graceful fallback (T6) |
| Pedagogy / rationale | 9 | 10 | tier rationale (T2) |
| Integration / handoff | 9 | 10 | consolidate triple-stated terminal rule (T5) |
| Adaptivity / escape hatches | 6 | 9 | tiers + fast-path (T2) + override (T3) |

7-dimension mean before ≈ 8.7 (≈88). After ≈ 9.6 (≈96). Threshold ≥95 met with margin.

---

## File Structure

- Create: `.claude/skills/brainstorming/SKILL.md` — forked + improved skill (edited in T2–T6)
- Create: `.claude/skills/brainstorming/visual-companion.md` — copied verbatim, fallback subsection added in T6
- Create: `.claude/skills/brainstorming/spec-document-reviewer-prompt.md` — copied verbatim
- Create: `.claude/skills/brainstorming/scripts/*` — copied verbatim (companion server; needed for a functional fork)
- Create: `docs/superpowers/brainstorming-skill-rubric.md` — scoring rubric + acceptance criteria (the verification instrument)

Each task ends with an independently checkable deliverable (a rubric criterion flips red→green) and a commit.

---

### Task 1: Vendor the upstream skill + write the rubric (the test instrument)

**Files:**
- Create: `.claude/skills/brainstorming/` (copied tree)
- Create: `docs/superpowers/brainstorming-skill-rubric.md`

**Interfaces:**
- Produces: a verbatim fork (the "red" baseline) and a rubric whose criteria are referenced by every later task's verification step.

- [ ] **Step 1: Copy the upstream skill tree into the repo**

```bash
SRC=~/.claude/plugins/cache/claude-plugins-official/superpowers/6.0.3/skills/brainstorming
DST=.claude/skills/brainstorming
mkdir -p "$DST"
cp -R "$SRC"/. "$DST"/
ls "$DST" "$DST/scripts"
```
Expected: `SKILL.md`, `visual-companion.md`, `spec-document-reviewer-prompt.md`, `scripts/` present.

- [ ] **Step 2: Write the rubric with grep-checkable acceptance criteria (these are the "failing tests")**

Create `docs/superpowers/brainstorming-skill-rubric.md`:

```markdown
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
```

- [ ] **Step 3: Run the acceptance checks to verify they FAIL (red baseline)**

```bash
cd "$(git rev-parse --show-toplevel)"
grep -q "Right-Sizing the Process" .claude/skills/brainstorming/SKILL.md && echo "AC2-tiers GREEN (unexpected)" || echo "AC2-tiers RED (expected)"
grep -qi "User override" .claude/skills/brainstorming/SKILL.md && echo "AC3 GREEN (unexpected)" || echo "AC3 RED (expected)"
grep -qi "genuinely competitive" .claude/skills/brainstorming/SKILL.md && echo "AC4 GREEN (unexpected)" || echo "AC4 RED (expected)"
grep -qi "fall back to text" .claude/skills/brainstorming/SKILL.md && echo "AC6 GREEN (unexpected)" || echo "AC6 RED (expected)"
```
Expected: all four print `RED (expected)`. (Upstream lacks these.)

- [ ] **Step 4: Confirm the verbatim copy preserves the activation description**

```bash
diff <(sed -n '1,4p' ~/.claude/plugins/cache/claude-plugins-official/superpowers/6.0.3/skills/brainstorming/SKILL.md) \
     <(sed -n '1,4p' .claude/skills/brainstorming/SKILL.md)
```
Expected: no output (identical frontmatter).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/brainstorming docs/superpowers/brainstorming-skill-rubric.md
git commit -F - <<'EOF'
chore(skills): vendor brainstorming skill fork + scoring rubric

Verbatim copy of superpowers:brainstorming v6.0.3 as a project-local
override, plus a grep-checkable rubric (target >=95) used as the
acceptance test for the subsequent edits. Baseline criteria are red.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: Add tiered ceremony + fast-path (Adaptivity 6→9, Pedagogy 9→10)

**Files:**
- Modify: `.claude/skills/brainstorming/SKILL.md` (insert a section after the "Anti-Pattern" section)

**Interfaces:**
- Consumes: the HARD-GATE (must remain intact above this section).
- Produces: a `## Right-Sizing the Process` section satisfying AC2-tiers and AC2-fastpath.

- [ ] **Step 1: Add the acceptance check (already in rubric) and confirm it is red**

```bash
grep -q "Right-Sizing the Process" .claude/skills/brainstorming/SKILL.md && echo GREEN || echo RED
```
Expected: `RED`.

- [ ] **Step 2: Insert the new section immediately after the "Anti-Pattern: This Is Too Simple..." section**

Insert this block (verbatim, British English):

```markdown
## Right-Sizing the Process

The gate is non-negotiable; the *ceremony* scales to the work. State which tier you are using:

- **Trivial** (one-line change, config tweak, single obvious function): skip multiple-choice questioning. Go straight to a 2–3 sentence design, get a yes/no approval, then proceed. No spec doc unless the user wants one — the approval message IS the design record, and steps 6–8 of the checklist collapse into that approval.
- **Standard** (a feature, a component, a non-obvious change): run the full flow below — questions one at a time, approaches, sectioned design, committed spec doc, written-spec review.
- **Multi-subsystem** (several independent pieces): decompose first (see scope guidance), then run **Standard** on the first sub-project.

Scaling ceremony is not skipping rigour: the cheapest projects are where a wrong unexamined assumption is also cheapest to surface, so a trivial design is short, not absent.

**Fast-path for complete input:** If the user's request already answers purpose, constraints, and success criteria, do NOT re-ask them. Acknowledge what you already have, fill only genuine gaps with at most one or two questions, and move to the design. Re-interrogating a user who pre-empted the questions is wasted ceremony, not diligence.
```

- [ ] **Step 3: Verify the gate above is still intact and the tier section references it**

```bash
grep -q "HARD-GATE" .claude/skills/brainstorming/SKILL.md && echo "gate present" || echo "GATE MISSING"
grep -q "The gate is non-negotiable" .claude/skills/brainstorming/SKILL.md && echo "tier links to gate"
```
Expected: `gate present` and `tier links to gate`.

- [ ] **Step 4: Run acceptance checks (red→green)**

```bash
grep -q "Right-Sizing the Process" .claude/skills/brainstorming/SKILL.md && echo "AC2-tiers GREEN"
grep -qi "Fast-path for complete input" .claude/skills/brainstorming/SKILL.md && echo "AC2-fastpath GREEN"
```
Expected: both `GREEN`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/brainstorming/SKILL.md
git commit -F - <<'EOF'
feat(skills): scale brainstorming ceremony with tiers and a fast-path

Trivial/Standard/Multi-subsystem tiers plus a fast-path that skips
re-asking questions the user already answered. The design+approval gate
is preserved; only the ceremony scales. Addresses the adaptivity gap.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: Add an explicit user-override clause (Discipline 9→10, Adaptivity)

**Files:**
- Modify: `.claude/skills/brainstorming/SKILL.md` (the `<HARD-GATE>` block)

**Interfaces:**
- Consumes: the existing HARD-GATE text.
- Produces: a `User override` clause satisfying AC3-override, consistent with `using-superpowers`' instruction-priority rule (user instructions outrank skills).

- [ ] **Step 1: Confirm AC3 is red**

```bash
grep -qi "User override" .claude/skills/brainstorming/SKILL.md && echo GREEN || echo RED
```
Expected: `RED`.

- [ ] **Step 2: Replace the HARD-GATE block**

Find:

```markdown
<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>
```

Replace with:

```markdown
<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.

**User override:** User instructions outrank this skill. If the user explicitly opts out ("just build it, skip the design"), honour it — state in one line what you are skipping and the risk it carries, then proceed. Do not re-litigate. Absent an explicit opt-out, the gate holds.
</HARD-GATE>
```

- [ ] **Step 3: Verify the gate default is unchanged for the non-override path**

```bash
grep -q "Absent an explicit opt-out, the gate holds" .claude/skills/brainstorming/SKILL.md && echo "default preserved"
```
Expected: `default preserved`.

- [ ] **Step 4: Run acceptance check (red→green)**

```bash
grep -qi "User override" .claude/skills/brainstorming/SKILL.md && echo "AC3-override GREEN"
```
Expected: `GREEN`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/brainstorming/SKILL.md
git commit -F - <<'EOF'
feat(skills): add user-override clause to brainstorming hard-gate

Resolves the deadlock when a user explicitly says "skip the design":
honour the instruction (it outranks the skill), note the risk, proceed.
The gate still holds by default.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 4: Make alternatives conditional, not mandatory (Discipline/Pedagogy + YAGNI)

**Files:**
- Modify: `.claude/skills/brainstorming/SKILL.md` (checklist step 4; "Exploring approaches"; Key Principles "Explore alternatives")

**Interfaces:**
- Produces: conditional-approaches phrasing satisfying AC4-cond and AC4-noabs.

- [ ] **Step 1: Confirm AC4 is red**

```bash
grep -qi "genuinely competitive" .claude/skills/brainstorming/SKILL.md && echo GREEN || echo RED
grep -q "Always propose 2-3 approaches before settling" .claude/skills/brainstorming/SKILL.md && echo "absolute still present"
```
Expected: `RED` and `absolute still present`.

- [ ] **Step 2: Edit checklist step 4**

Find: `4. **Propose 2-3 approaches** — with trade-offs and your recommendation`

Replace with: `4. **Propose approaches** — when more than one is genuinely competitive, give 2–3 with trade-offs and your recommendation; when one is clearly right, name it with a one-line rationale and the closest alternative you rejected`

- [ ] **Step 3: Edit the "Exploring approaches" bullets**

Find:

```markdown
- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why
```

Replace with:

```markdown
- When more than one approach is genuinely competitive, propose 2–3 with trade-offs; do not manufacture strawman options when one approach is clearly correct
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why; if you rejected obvious alternatives, say why in one line
```

- [ ] **Step 4: Edit the Key Principles line**

Find: `- **Explore alternatives** - Always propose 2-3 approaches before settling`

Replace with: `- **Explore alternatives when they compete** - propose 2–3 only when more than one is genuinely viable; manufacturing strawmen wastes a turn (YAGNI applies to options too)`

- [ ] **Step 5: Run acceptance checks (red→green)**

```bash
grep -qi "genuinely competitive" .claude/skills/brainstorming/SKILL.md && echo "AC4-cond GREEN"
grep -q "Always propose 2-3 approaches before settling" .claude/skills/brainstorming/SKILL.md && echo "AC4-noabs RED (FAIL)" || echo "AC4-noabs GREEN"
```
Expected: `AC4-cond GREEN` and `AC4-noabs GREEN`.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/brainstorming/SKILL.md
git commit -F - <<'EOF'
fix(skills): make brainstorming alternatives conditional, not mandatory

Propose 2-3 approaches only when more than one genuinely competes;
otherwise name the clear choice and the rejected runner-up. Removes the
tension between "always propose 2-3" and "YAGNI ruthlessly".

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 5: Consolidate the triple-stated terminal-state rule (Integration 9→10)

**Files:**
- Modify: `.claude/skills/brainstorming/SKILL.md` (remove the standalone redundant paragraph after the flow graph)

**Interfaces:**
- Produces: one canonical prose statement of "only writing-plans next", satisfying AC5-dedup. The checklist step 9 and the flow-graph terminal node remain as the structural references; the "Implementation" bullet remains as the canonical prose.

- [ ] **Step 1: Confirm the redundant standalone line exists**

```bash
grep -c "The terminal state is invoking writing-plans" .claude/skills/brainstorming/SKILL.md
```
Expected: `1`.

- [ ] **Step 2: Delete the redundant paragraph after the dot graph**

Find and delete this paragraph (the one immediately after the closing ``` of the digraph):

```markdown
**The terminal state is invoking writing-plans.** Do NOT invoke frontend-design, mcp-builder, or any other implementation skill. The ONLY skill you invoke after brainstorming is writing-plans.
```

Rationale: the flow-graph terminal node already shows `Invoke writing-plans skill` as a `doublecircle`, and the "Implementation" section bullet ("Do NOT invoke any other skill. writing-plans is the next step.") states it canonically. This paragraph is the redundant third copy.

- [ ] **Step 3: Verify the canonical statement still exists exactly once in prose**

```bash
grep -q "writing-plans is the next step" .claude/skills/brainstorming/SKILL.md && echo "canonical prose present"
grep -c "The terminal state is invoking writing-plans" .claude/skills/brainstorming/SKILL.md
```
Expected: `canonical prose present` and count `0`.

- [ ] **Step 4: Run acceptance check (red→green)**

```bash
[ "$(grep -c "The terminal state is invoking writing-plans" .claude/skills/brainstorming/SKILL.md)" = "0" ] && echo "AC5-dedup GREEN"
```
Expected: `GREEN`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/brainstorming/SKILL.md
git commit -F - <<'EOF'
refactor(skills): de-duplicate brainstorming terminal-state rule

The "only writing-plans next" rule was stated three times. Keep the
canonical prose bullet and the flow-graph terminal node; drop the
redundant standalone paragraph.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 6: Add graceful fallback for the visual companion (Progressive disclosure 9→10)

**Files:**
- Modify: `.claude/skills/brainstorming/SKILL.md` (Visual Companion section — one line)
- Modify: `.claude/skills/brainstorming/visual-companion.md` (add a `## Fallback` subsection)

**Interfaces:**
- Produces: fallback guidance in both files, satisfying AC6-skillfb and AC6-vcfb.

- [ ] **Step 1: Confirm AC6 is red in both files**

```bash
grep -qi "fall back to text" .claude/skills/brainstorming/SKILL.md && echo "skill GREEN" || echo "skill RED"
grep -qi "## Fallback" .claude/skills/brainstorming/visual-companion.md && echo "vc GREEN" || echo "vc RED"
```
Expected: both `RED`.

- [ ] **Step 2: Add a fallback line to the SKILL.md Visual Companion section**

Append this line to the end of the "Visual Companion" section in SKILL.md (after the line that points to `visual-companion.md`):

```markdown
**If the companion cannot start** (no Node, port in use, no browser), say so in one line and fall back to text and ASCII sketches — never block the session on the visual tool.
```

- [ ] **Step 3: Add a Fallback subsection to visual-companion.md**

Append to the end of `.claude/skills/brainstorming/visual-companion.md`:

```markdown
## Fallback — when the companion will not start

The visual companion is optional. If it fails, degrade gracefully and keep brainstorming in the terminal:

- **No Node / `node` not found** → tell the user in one line, continue text-only with ASCII layout sketches and lettered options.
- **Port already in use** → try `stop-server.sh` once; if it still fails, fall back to text-only rather than hunting ports.
- **No browser opens** → give the user the local URL once; if they cannot open it, fall back to text-only.
- **Any other error** → do not retry more than once and never block the design flow on the tool. The companion is a convenience, not a dependency; the gate and the design flow proceed without it.
```

- [ ] **Step 4: Run acceptance checks (red→green)**

```bash
grep -qi "fall back to text" .claude/skills/brainstorming/SKILL.md && echo "AC6-skillfb GREEN"
grep -qi "## Fallback" .claude/skills/brainstorming/visual-companion.md && echo "AC6-vcfb GREEN"
```
Expected: both `GREEN`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/brainstorming/SKILL.md .claude/skills/brainstorming/visual-companion.md
git commit -F - <<'EOF'
feat(skills): graceful fallback for brainstorming visual companion

If the companion server cannot start (no Node, port busy, no browser),
degrade to text/ASCII and continue — the tool is a convenience, not a
dependency. Documented in SKILL.md and visual-companion.md.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 7: Final re-score, self-review, and discoverability check

**Files:**
- Modify: `docs/superpowers/brainstorming-skill-rubric.md` (record final scores)

**Interfaces:**
- Consumes: every prior task's acceptance criteria.
- Produces: a recorded final score ≥95 and confirmation the skill is well-formed and discoverable.

- [ ] **Step 1: Run ALL acceptance checks green**

```bash
cd "$(git rev-parse --show-toplevel)"
S=.claude/skills/brainstorming/SKILL.md
V=.claude/skills/brainstorming/visual-companion.md
fail=0
grep -q "Right-Sizing the Process" $S || { echo "AC2-tiers FAIL"; fail=1; }
grep -qi "Fast-path for complete input" $S || { echo "AC2-fastpath FAIL"; fail=1; }
grep -qi "User override" $S || { echo "AC3 FAIL"; fail=1; }
grep -qi "genuinely competitive" $S || { echo "AC4-cond FAIL"; fail=1; }
grep -q "Always propose 2-3 approaches before settling" $S && { echo "AC4-noabs FAIL"; fail=1; }
[ "$(grep -c "The terminal state is invoking writing-plans" $S)" = "0" ] || { echo "AC5 FAIL"; fail=1; }
grep -qi "fall back to text" $S || { echo "AC6-skillfb FAIL"; fail=1; }
grep -qi "## Fallback" $V || { echo "AC6-vcfb FAIL"; fail=1; }
[ $fail = 0 ] && echo "ALL ACCEPTANCE CHECKS GREEN" || echo "SOME CHECKS FAILED"
```
Expected: `ALL ACCEPTANCE CHECKS GREEN`.

- [ ] **Step 2: Confirm activation description is unchanged and the file is well-formed**

```bash
diff <(sed -n '1,4p' ~/.claude/plugins/cache/claude-plugins-official/superpowers/6.0.3/skills/brainstorming/SKILL.md) \
     <(sed -n '1,4p' $S) && echo "description identical"
grep -q "HARD-GATE" $S && echo "gate intact"
grep -q "name: brainstorming" $S && echo "name set"
```
Expected: `description identical`, `gate intact`, `name set`.

- [ ] **Step 3: Self-review against the spec (the five weaknesses)**

Confirm each evaluation weakness has a corresponding edit:
1. No fast-path → Task 2 (tiers + fast-path) ✔
2. No override path → Task 3 (User override clause) ✔
3. Mandatory 2-3 approaches → Task 4 (conditional) ✔
4. Triple-stated terminal rule → Task 5 (de-dup) ✔
5. No companion fallback → Task 6 (fallback in both files) ✔

Placeholder scan: `grep -niE "TBD|TODO|FIXME|fill in" $S $V` → expected: no output.

- [ ] **Step 4: Record final scores in the rubric**

Append to `docs/superpowers/brainstorming-skill-rubric.md`:

```markdown
## Final score (post-implementation)

| Dimension | Score |
|---|---|
| Activation | 9 |
| Discipline | 10 |
| Structure | 10 |
| Progressive disclosure | 10 |
| Pedagogy | 10 |
| Integration | 10 |
| Adaptivity | 9 |

**Mean ≈ 9.7 → 97/100 (≥95 target met).**
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/brainstorming-skill-rubric.md
git commit -F - <<'EOF'
docs(skills): record brainstorming fork final score (97/100)

All acceptance criteria green; five evaluation weaknesses resolved.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review (plan vs spec)

**1. Spec coverage:** The spec is the five evaluation weaknesses + the ≥95 target. Mapping: W1→T2, W2→T3, W3→T4, W4→T5, W5→T6, target verification→T1 (rubric) & T7 (final). All covered.

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" steps; every edit shows the exact text to insert and the exact grep to verify.

**3. Consistency:** Acceptance-criterion IDs (AC2…AC6) are defined in T1's rubric and reused verbatim in T2–T7. `grep` strings in verification steps match the literal text inserted in the edit steps (e.g. "genuinely competitive", "User override", "fall back to text", "Right-Sizing the Process"). Source path `superpowers/6.0.3/skills/brainstorming` is used consistently in T1, T2-step diff, and T7.

**Note on scoring subjectivity:** the rubric is a heuristic, not a build gate. "≥95" is demonstrated by (a) all acceptance criteria green and (b) the per-dimension target table; a reviewer may weight dimensions differently, but every concrete defect from the evaluation is closed.
