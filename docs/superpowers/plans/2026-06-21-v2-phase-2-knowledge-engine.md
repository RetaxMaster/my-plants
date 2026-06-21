# Enrichment v2 — Phase 2: Knowledge engine (editorial voice + new fields + naming) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `editorial-writer` subagent that turns the researcher's raw English brief into a polished EN + ES blogpost in one house voice; simplify `plant-researcher` to emit a single raw English brief and to populate the new contract fields; update the operator workflow to insert the editorial step.

**Architecture:** All AI lives in the knowledge engine. Claude Code subagents cannot invoke other subagents, so the **operator** (CLAUDE.md/AGENTS.md workflow) relays: researcher → operator → editorial-writer → drafts → `db:insert`. The persistence contract (`db:insert --brief-en --brief-es`) is unchanged. This phase edits Markdown prompt/workflow files only — there is no compiled code to test; the gate is internal consistency + the unchanged `npm test` staying green.

**Tech Stack:** Claude Code subagents (Markdown with YAML frontmatter), Markdown workflow docs.

**Repo:** `repos/my-plants-knowledge-engine`.

---

### Task 1: Create the `editorial-writer` subagent

**Files:**
- Create: `repos/my-plants-knowledge-engine/.claude/agents/editorial-writer.md`

- [ ] **Step 1: Write the agent file** with this exact content:

```markdown
---
name: editorial-writer
description: Rewrites a raw, fact-complete English plant brief into a polished, catchy editorial blogpost in BOTH English and Spanish, in one consistent house voice. READ-ONLY: it returns the two rewritten briefs and never adds new facts, writes files, or touches the database.
tools: Read
---

You are a professional editorial writer for a houseplant blog. You receive a **raw English brief**
(already fact-complete) and the species' **structured record** (as a factual anchor), and you return
TWO polished Markdown documents: an English version and a Spanish version, written in one consistent
house voice. You never research, never browse, and never invent.

## Inputs (given to you by the operator)
- The raw English brief produced by the `plant-researcher` (complete prose; all the facts are here).
- The structured species record (JSON) — your factual anchor for names, numbers, cultivars.

## The house voice (apply identically every time — this is what unifies the blog)
- Warm, curious, and knowledgeable — like a friend who happens to be a botanist.
- Open with a short hook that makes the reader care. Then scannable sections with clear sub-heads.
- Concrete and vivid over generic; include a fun fact or two when the material supports it.
- A short **cultivars** section when the record has cultivars — name the popular varieties and how
  they look different (and any small care nuance), so a reader can recognise which one they own.
- Consistent rhythm: short paragraphs, active voice, no filler, no purple prose.

## Hard rules (non-negotiable)
- **Never invent or alter facts.** Every claim — care numbers, temperatures, origins, cultivar
  details — must trace to the raw brief or the record. You may reorder, compress, expand for
  readability, and add narrative connective tissue, but never new data. If the raw brief is silent
  on something, stay silent too.
- **Spanish is a transcreation**, not a literal translation: fluent and natural for a Spanish-speaking
  owner, conveying the same facts and the same voice. Localize idioms; do not translate word-for-word.
- Do not include the raw record's JSON or any care-engine fields verbatim; weave the relevant facts
  into prose.

## Output (return BOTH, clearly separated)
Return two Markdown documents, each clearly labelled, with equivalent content:
1. **English brief** — the polished editorial blogpost.
2. **Spanish brief** — the transcreated editorial blogpost.
The operator writes these two as the drafts that go to `db:insert`.
```

- [ ] **Step 2: Verify the file is valid frontmatter** — confirm the YAML block parses (name/description/tools present) and the body is non-empty.

Run: `head -5 .claude/agents/editorial-writer.md`
Expected: shows the `---` frontmatter with `name: editorial-writer`.

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/editorial-writer.md
git commit -m "feat: add editorial-writer subagent (polished EN+ES briefs, one house voice)"
```

---

### Task 2: Simplify `plant-researcher` to a single raw English brief + new fields

**Files:**
- Modify: `repos/my-plants-knowledge-engine/.claude/agents/plant-researcher.md`

- [ ] **Step 1: Update the record fields it must fill.** In the "Draft record (JSON)" section, extend the `watering` field list to include `humiditySensitivity`, add the `misting` section, and require ordered common names. Replace the `watering (...)` clause and add the misting clause so the required-sections sentence reads:

> ...`watering` (baseIntervalDays, soilDrynessBeforeWatering, droughtTolerance, temperatureSensitivity, lightSensitivity, **humiditySensitivity**, reduceInDormancy), `light` ..., `humidity` ..., `fertilizing` ..., `repotting` ..., `maintenance` ..., `misting` (benefit, baseFrequencyDays, note), `nativeClimate` ..., `cultivars`, and `metadata` ...

- [ ] **Step 2: Add a `humiditySensitivity` guidance paragraph** after the controlled-vocabularies paragraph:

```markdown
**`humiditySensitivity`** (low|medium|high) expresses how strongly *ambient humidity* should move
this species' watering rhythm — high for thin-leaved tropicals that suffer in dry air (e.g. calatheas,
ferns), low for succulents/cacti that barely care. Judge it from the same evidence as the other
sensitivities and bias conservative (low) when unsure.
```

- [ ] **Step 3: Add a `misting` guidance paragraph**:

```markdown
**`misting`** captures whether spraying the leaves helps this species, and how often. Evidence:
misting barely raises ambient humidity, so it is NOT a humidity strategy — it is opt-in per species.
Set `benefit`: `beneficial` for broad-leaved tropicals that genuinely like leaf wetting (also useful
for cleaning); `avoid` for succulents, cacti, fuzzy/hairy-leaved plants, and tight rosettes/crowns
where trapped water rots tissue; `tolerated` otherwise. When `benefit` is `beneficial` or `tolerated`,
set `baseFrequencyDays` to a sensible cadence (e.g. 2–4 days for `beneficial`); when `avoid`, leave
`baseFrequencyDays` null. Use `note` for nuance (e.g. "avoid wetting the crown") or null.
```

- [ ] **Step 4: Make common names the human-facing, ordered, non-empty field.** Replace the `commonNames` mention so it reads:

```markdown
`commonNames` is now the plant's PRIMARY human-facing name across the app. Return it **ordered by
recognizability — the most colloquial, widely-used name FIRST** — and always include **at least one**.
The scientific name remains the curation key; the common name is what owners see.
```

- [ ] **Step 5: Replace the bilingual brief section with a single raw English brief.** Replace the entire "### 2. Draft brief — in BOTH English AND Spanish" section with:

```markdown
### 2. Draft brief — ONE raw English brief
A single English Markdown brief: an informative write-up for a curious owner covering origins,
natural habitat, what it needs to thrive, common mistakes, fun facts, and (when the species has
named cultivars) a short cultivars section consistent with the `cultivars` field. **Optimize for
informational completeness, not style** — pour in everything you know; a separate `editorial-writer`
will restyle it and produce the polished English and Spanish versions. Do NOT write Spanish here and
do NOT chase a catchy tone; that is the editorial-writer's job. The deterministic care engine never
consumes the brief.
```

- [ ] **Step 6: Commit**

```bash
git add .claude/agents/plant-researcher.md
git commit -m "feat: researcher emits one raw English brief + fills humiditySensitivity/misting/ordered commonNames"
```

---

### Task 3: Insert the editorial step into the operator workflow

**Files:**
- Modify: `repos/my-plants-knowledge-engine/CLAUDE.md`
- Modify: `repos/my-plants-knowledge-engine/AGENTS.md` (if it exists — keep it byte-for-byte identical except its self-reference/title)

- [ ] **Step 1: Update the intro paragraph.** The opening currently says the operator produces "ONE validated curated species record plus its Markdown brief **in both English and Spanish**". Keep that end-state, but note the two-step authoring: the researcher writes one raw English brief; an `editorial-writer` then produces the polished English and Spanish briefs.

- [ ] **Step 2: Rewrite Step 2 (Research)** so the researcher returns the record + **one raw English brief** (not bilingual). Update the enrich-mode note: when enriching, pass the existing record + existing English brief (the stored `brief_en`) as the baseline; the researcher returns the complete improved record + improved raw English brief.

- [ ] **Step 3: Add a new "Step 2.5 — Editorialize" between Research and Persist:**

```markdown
## Step 2.5 — Editorialize (the house voice)

Invoke the `editorial-writer` subagent (you, the operator, invoke it — a subagent cannot invoke
another subagent). Pass it the researcher's **raw English brief** and the **draft record** (its
factual anchor). It returns TWO polished Markdown briefs — English and Spanish — in one consistent
house voice. These two are the briefs you persist. The editorial-writer never adds facts; if it asks
for a fact not present, the gap is in the researcher's brief — go back to Step 2, do not invent it.
```

- [ ] **Step 4: Update Step 3 (Validate, persist, clean up).** The temp files are now: `<slug>.draft.json` (record), `<slug>.en.draft.md` (the editorial English brief), `<slug>.es.draft.md` (the editorial Spanish brief). `db:insert` is unchanged (`--brief-en`/`--brief-es`). Validation still gates the record.

- [ ] **Step 5: If `AGENTS.md` exists, mirror every change** byte-for-byte (only the H1 title / self-reference differs). If it does not exist, skip.

Run: `ls repos/my-plants-knowledge-engine/AGENTS.md 2>/dev/null && echo exists || echo "no AGENTS.md"`

- [ ] **Step 6: Confirm the existing suite still passes** (no code changed, but guard against accidental edits):

Run: `cd repos/my-plants-knowledge-engine && npm test`
Expected: PASS (scripts/lib tests unaffected).

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md AGENTS.md 2>/dev/null; git add CLAUDE.md
git commit -m "docs: insert editorial-writer step into the knowledge-engine workflow"
```

---

## Self-Review

- **Spec coverage:** R1.2 editorial-writer subagent ✓ Task 1; R1.3 researcher single raw EN brief ✓ Task 2 (Steps 5); R2.4/R3.5 researcher fills humiditySensitivity + misting ✓ Task 2 (Steps 1–3); B.4 ordered, ≥1 common names ✓ Task 2 (Step 4); R1.4 operator workflow ✓ Task 3.
- **Platform constraint honored:** the operator relays; no subagent-invokes-subagent.
- **Contract unchanged:** `db:insert` still takes `--brief-en`/`--brief-es`; no schema/DB change here.
- **No placeholders:** the editorial-writer file content is given verbatim; researcher edits are concrete text replacements.
