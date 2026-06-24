# WORKING-SESSION.md — Cortex Agent Build Runbook

A phase-driven runbook for building a production-ready Cortex Agent from this dbt
template. It works two ways at once:

- **For you (human):** read top-to-bottom as the session guide — each phase states
  what you decide and what gets built.
- **For Cortex Code (Coco):** an executable script. Point Coco at this file with
  *"Follow WORKING-SESSION.md"* and it will drive all five phases, pausing at each
  gate for your input and running the build commands live.

---

## Operating Rules (the contract Coco follows)

1. **Infer-vs-specify gate — before each phase.** Coco MUST ask whether you want it
   to *infer* the values from your data, or whether you'll *specify* them explicitly.
   Never assume.
2. **Materialize gate — at the end of each phase.** Coco runs the dbt command that
   creates the object (semantic view, agent, evaluation) and confirms success.
3. **Never advance past a failing gate.** If a build/create/eval command errors, stop,
   surface the error, fix it with the user, and re-run before moving on.
4. **One question set at a time.** Keep each phase's questions focused; capture the
   answers before authoring files.

---

## Prerequisites

Confirm these before Phase 0. If any are missing, resolve them first.

| Requirement | Check |
|---|---|
| Dependencies installed | `dbt deps` has been run (the `dbt_semantic_view` package is present) |
| Profile configured | `profiles.yml` has real `database`, `schema`, `warehouse`, `role` |
| Source data exists | The tables you'll model are queryable by your role |
| Cortex Agents enabled | Account has Cortex Agents + `CREATE SEMANTIC VIEW` / `CREATE AGENT` privileges |

---

## How Coco executes the gates

Coco detects the available execution path and uses it consistently:

- **Local dbt** (if `dbt` + a configured profile are available):
  `dbt build ...`, `dbt run-operation ...`, `dbt seed`
- **Deployed dbt project** (Snowflake Workspace / CLI):
  `snow dbt execute <project> --args '<the same dbt args>'`

Each phase below lists the canonical `dbt` command. When running via `snow dbt`, wrap
the same arguments in `snow dbt execute <project> --args '...'`. Coco confirms each
command succeeded (object created, model built, eval started) before advancing.

---

## Phase 0 — Orientation

**Goal:** Lock in the target and the object names everything else will reference.

Coco asks:
- "Confirm target from `profiles.yml`: which `database.schema`, `warehouse`, and `role`?"
- "What should we name the **semantic view**, the **agent**, and the **evaluation run**?"
- Gate: "Should I **infer** these from your environment/conventions, or will you **specify** them?"

Coco records (used by every later phase):
- `target` (dev/prod) and resolved `<db>.<schema>`
- `sv_<name>` — semantic view model name
- `<agent_name>` — agent spec file `agents/<agent_name>.yml`
- `<run_name>` — evaluation run label

**Done when:** names + target are confirmed and written down for reuse.

---

## Phase 1 — Business Questions → Semantic Views

**Goal:** Capture the ~10 questions the agent must answer, then model the data to support them.

Coco asks first:
- "What are the ~10 business questions, and which table(s)/columns answer each?"
- Gate: "Should I **infer** the dimensions/metrics from your source tables, or will you **specify** them?"

Files Coco edits:
- `models/sources.yml` — declare source `database`, `schema`, and tables
- `models/staging/stg_*.sql` — optional cleanup/conforming models
- `models/semantic_views/sv_<name>.sql` — the following clauses in order:
  1. `TABLES` — logical table definitions with primary keys
  2. `RELATIONSHIPS` — foreign key joins between tables
  3. `FACTS` — row-level expressions metrics aggregate over (must precede `DIMENSIONS`/`METRICS`)
  4. `DIMENSIONS` — filterable/groupable attributes
  5. `METRICS` — aggregate measures (SUM, COUNT, AVG, etc.)
  6. `AI_SQL_GENERATION` — business rules for SQL generation (e.g. default date handling, rounding conventions)
  7. `AI_QUESTION_CATEGORIZATION` — guardrails for out-of-scope questions (e.g. reject HR or PII queries)
  8. `AI_VERIFIED_QUERIES` — confirmed Q&A pairs that seed the agent's onboarding questions

Coco asks for `AI_SQL_GENERATION` and `AI_QUESTION_CATEGORIZATION` content explicitly:
- "What SQL generation rules should always apply (e.g. default to most recent date, round currency to 2 decimals)?"
- "What question categories are out of scope and should be rejected?"

**Materialize gate (run live):**
```bash
dbt build --select sv_<name>
```

**Done when:** the semantic view exists in `<db>.<schema>` and a sample
`SELECT ... FROM SEMANTIC_VIEW(sv_<name> ...)` returns rows.

---

## Phase 2 — Agent Reasoning → Orchestration

**Goal:** Define how the agent reasons and routes between tools.

> Phases 2–4 all author into the **same file**: `agents/<agent_name>.yml`.
> The agent object is created once at the **end of Phase 4** — that is the single create gate.

Coco asks:
- "How should the agent work through reasoning? When should it use each tool vs. answer directly?"
- Gate: "Should I **infer** the orchestration logic from your questions/tools, or will you **specify** it?"

Files Coco edits (in `agents/<agent_name>.yml`):
- `instructions.orchestration` — routing/reasoning guidance
- `orchestration.budget` — `seconds` / `tokens` if non-default
- `models.orchestration` — leave `auto` unless told otherwise

**Materialize gate:** none yet — continue to Phase 3. (Object is created at end of Phase 4.)

**Done when:** the orchestration block reflects the agreed reasoning strategy.

---

## Phase 3 — Agent Response → Response Instructions

**Goal:** Define how the agent talks to users.

Coco asks:
- "How should the agent respond — tone, format, level of detail, citations?"
- Gate: "Should I **infer** the response style from the use case, or will you **specify** it?"

Files Coco edits (in `agents/<agent_name>.yml`):
- `instructions.response` — response style and rules
- `instructions.sample_questions` — 3+ representative starter questions

**Materialize gate:** none yet — continue to Phase 4.

**Done when:** response instructions + sample questions are filled in.

---

## Phase 4 — Agent Tools → Tool Descriptions

**Goal:** Wire up the tools and their resources, then create the agent.

Coco asks:
- "What tools does this agent need (Cortex Analyst, Cortex Search, others)?"
- "For each tool, what should it be used for — and explicitly NOT used for?"
- Gate: "Should I **infer** tool descriptions/resources from the semantic view + use case, or will you **specify** them?"

Files Coco edits (in `agents/<agent_name>.yml`):
- `tools[].tool_spec` — `type`, `name`, and a precise `description` (descriptions
  drive routing accuracy — say what each tool does AND does not do)
- `tool_resources` — point the Analyst tool at `<db>.<schema>.SV_<NAME>`; configure
  Search service name/`max_results` if used

**Materialize gate (run live — creates the agent):**
```bash
dbt run-operation create_agent --args '{agent_name: <agent_name>}'
```
For later zero-downtime edits to a live agent, use:
```bash
dbt run-operation alter_agent --args '{agent_name: <agent_name>}'
```

**Done when:** `<db>.<schema>.<AGENT_NAME>` exists and answers a sample question.

---

## Phase 5 — Evaluation Dataset → Eval Workflow

**Goal:** Turn the confirmed questions + answers into a measurable evaluation run.

Coco asks:
- "We confirmed ~10 questions and their answers earlier — use those as ground truth?"
- Gate: "Should I **infer** ground-truth answers from your data, or will you **specify** them?"

Files Coco edits:
- `seeds/eval_ground_truth.csv` — `input_query` + `ground_truth_json`
  (JSON must be a valid object, e.g. `{"ground_truth_output": "..."}`)
- `models/evaluations/eval_dataset.sql` — keep `PARSE_JSON(...)` so `ground_truth`
  is **VARIANT** (do NOT use `OBJECT_CONSTRUCT`)
- `evaluations/<config>.yml` — set `dataset.table_name` to `<db>.<schema>.EVAL_DATASET`
  and `agent_params.agent_name` to `<AGENT_NAME>`

**Materialize gate (run live):**
```bash
dbt seed
dbt run --select eval_dataset
dbt run-operation run_evaluation --args '{agent_name: <agent_name>, run_name: <run_name>, config_file: <config>.yml}'
```

**Done when:** the evaluation run starts and returns scores.

---

## Wrap-up — Review & Ship

- **Review scores** from the evaluation. Target **≥ 95%** answer correctness before
  shipping. If short, refine the semantic view (verified queries, synonyms) or the
  agent instructions, then re-run Phases 4–5.
- **Iterate live** with `alter_agent` (zero-downtime) rather than recreating.
- **Ship** to your surface: Snowflake Intelligence, Microsoft Teams, the Cortex Agent
  REST API, or MCP. (See `docs/agent-lifecycle-guide.html`.)
- **Schedule** recurring builds/evals with Snowflake Tasks (see `README.md`).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Eval errors with *"dataset already exists"* | Remove the entire `dataset:` block from `evaluations/<config>.yml` after the first successful run. |
| `ground_truth` rejected / wrong type | It must be **VARIANT** — keep `PARSE_JSON(ground_truth_json)` in `eval_dataset.sql`; do not switch to `OBJECT_CONSTRUCT`. |
| Agent can't find the semantic view | `tool_resources.Analyst.semantic_view` must be the fully-qualified `<db>.<schema>.SV_<NAME>` that Phase 1 built. |
| Poor tool routing | Tighten each `tools[].description` — state what the tool is for AND what it is not for. |
| `dbt deps` can't reach the hub | Provide the External Access Integration name (see `README.md`). |
