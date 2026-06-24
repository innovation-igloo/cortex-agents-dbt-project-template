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
  6. `AI_SQL_GENERATION` — **how** the agent writes SQL: encode domain conventions the LLM cannot
     infer from column names alone. Keep instructions specific and concise — over-prompting degrades
     accuracy and increases token cost. Start minimal and add rules only when you observe failures.

     Good candidates:
     - Default time filters ("if no date is specified, return the last 30 days")
     - Fiscal calendar offsets ("our fiscal year starts in February")
     - Formatting rules ("round all currency to 2 decimal places")
     - Domain classification logic ("classify stock as CRITICAL <10, LOW 10–24, OK 25+")
     - Enum casing or encoding quirks ("region values are always uppercase")

  7. `AI_QUESTION_CATEGORIZATION` — **what to do with a question** before SQL is even attempted.
     This fires before SQL generation and is completely independent — adding it does not change
     your `AI_SQL_GENERATION` instructions at all (they are additive modules).

     Good candidates:
     - Reject out-of-scope topics ("Reject questions about employee data. Ask the user to contact HR.")
     - Table routing when multiple unrelated tables share the view ("If the question is about
       inventory, query the inventory table. If about sales, query the orders table.")
     - Ask for clarification on ambiguous questions ("If no product type is specified, mark the
       question UNCLEAR and ask the user to specify product_type.")
     - Special encoding guardrails ("entity names with apostrophes must use doubled single
       quotes '' in SQL — backslash escaping is not valid in Snowflake")

  8. `AI_VERIFIED_QUERIES` — confirmed Q&A pairs that seed the agent's onboarding questions

Coco asks for `AI_SQL_GENERATION` and `AI_QUESTION_CATEGORIZATION` content explicitly:
- "What SQL formatting or domain conventions should always apply? (e.g. fiscal calendar, rounding, default date range)"
- "Are there question types that should be rejected, routed to a specific table, or require clarification before the agent attempts SQL?"
- Gate: "Should I infer these rules from your data and questions, or will you specify them?"

> Both clauses are optional and additive — use neither, one, or both. Start with what you know
> is wrong today; add more rules as you discover gaps during testing.

**Materialize gate (run live):**
```bash
dbt build --select sv_<name>
```

**Done when:** the semantic view exists in `<db>.<schema>` and a sample
`SELECT ... FROM SEMANTIC_VIEW(sv_<name> ...)` returns rows.

---

## Phase 2 — Agent Reasoning → Orchestration

**Goal:** Define how the agent plans and routes between tools. This is the highest-impact accuracy lever after tool descriptions.

> Phases 2–4 all author into the **same file**: `agents/<agent_name>.yml`.
> The agent object is created once at the **end of Phase 4** — that is the single create gate.

Coco asks:
- "Walk me through the main question types this agent will face — which tool should handle each one?"
- "Are there multi-step flows where the agent needs to chain tool calls or call them in parallel?"
- "What should the agent say when data is unavailable, results are empty, or a question is ambiguous?"
- Gate: "Should I **infer** the orchestration logic from your questions and tools, or will you **specify** it?"

Files Coco edits (in `agents/<agent_name>.yml`):
- `instructions.orchestration` — the agent's planning and routing rules
- `orchestration.budget` — `seconds` / `tokens` if non-default
- `models.orchestration` — leave `auto` unless told otherwise

What belongs in `instructions.orchestration`:
- Tool selection logic — which tool handles which question type
- Data retrieval rules — time windows, default filters ("when user says 'recent', use last 30 days")
- User intent interpretation — how to disambiguate vague questions
- Tool call sequencing — which tools to run in order vs. in parallel
- Conditional logic — "if result > 100 rows, aggregate before displaying"
- Error and edge case handling — what to say when data is unavailable, empty, or ambiguous

What does NOT belong here (put these in `instructions.response` instead):
- Tone, formatting, chart rendering, table/bullet preferences, disclaimers

> Rule of thumb: if the instruction affects WHAT the agent does or WHICH tool it picks, it goes in
> orchestration. If it affects HOW the output looks, it goes in response.

> Keep instructions concise — if a coworker couldn't follow them, neither can the LLM.
> Use agent monitoring traces to diagnose routing failures and refine iteratively.

**Materialize gate:** none yet — continue to Phase 3. (Object is created at end of Phase 4.)

**Done when:** the orchestration block covers all major question types, error scenarios, and routing rules.

---

## Phase 3 — Agent Response → Response Instructions

**Goal:** Define how the agent formats and communicates its answers — completely separate from tool routing.

Coco asks:
- "Who is the primary audience? (executives, analysts, ops teams, etc.)"
- "What format do users expect — tables, bullets, charts, plain prose?"
- "Are there legal/compliance topics that need a disclaimer appended to answers?"
- Gate: "Should I **infer** the response style from the use case and audience, or will you **specify** it?"

Files Coco edits (in `agents/<agent_name>.yml`):
- `instructions.response` — response style, format, and communication rules
- `instructions.sample_questions` — 3+ representative starter questions

What belongs in `instructions.response`:
- **Tone** — "Be concise and professional. Lead with the direct answer, then supporting details.
  Avoid hedging language like 'it seems' — be direct with data."
- **Data presentation** — "Use tables for multi-row data (>3 items). Use charts for comparisons,
  trends, and rankings. Always include units (dollars, %, count) with numbers."
- **Response structure by question type** — "For 'What is X?' questions, lead with the direct answer.
  For 'Show me X', provide a brief summary then table/chart then key insights."
- **Disclaimers** — "When answering [topic]-related questions, always append: '[disclaimer text]'."
- **Error message style** — "When data is unavailable, explain the limitation and suggest alternatives."
- **Chart rendering** — "Whenever data can be rendered as a chart, default to chart even if the user
  didn't ask."

Advanced: different user roles often want different response styles (e.g. analysts want SQL shown,
business users don't). This can be handled with a role-based response instructions table + custom
tool — see the "Dynamic Response Instructions" pattern.

**Materialize gate:** none yet — continue to Phase 4.

**Done when:** response instructions cover tone, format, error handling, and any disclaimers; sample
questions reflect the top 3+ real questions end users will ask.

---

## Phase 4 — Agent Tools → Tool Descriptions

**Goal:** Wire up tools and their resources, then create the agent. Tool descriptions are the **single most critical factor** for agent accuracy — agents pick tools based on name and description alone, not by inspecting your data model.

Coco asks:
- "What tools does this agent need (Cortex Analyst, Cortex Search, custom tools)?"
- "For each tool: what data does it access, when should the agent use it, and critically — when should
  it NOT use it?"
- Gate: "Should I **infer** tool descriptions from the semantic view and use case, or will you **specify** them?"

Files Coco edits (in `agents/<agent_name>.yml`):
- `tools[].tool_spec.name` — keep names short and purpose-specific; names are loaded into the LLM
  context and influence selection
- `tools[].tool_spec.description` — the 4-part structure that drives accuracy:
  1. **What data it accesses** — a concise summary of what's in the semantic view or search index
  2. **When to use it** — specific question types and scenarios with examples
  3. **When NOT to use it** — this section is critical; without it the agent tries to use tools for
     everything remotely related
  4. **Data format / expectations** — units, date formats, key filter values
- `tool_resources` — point the Analyst tool at `<db>.<schema>.SV_<NAME>`; configure Search service
  name/`max_results` if used

Common failure patterns and fixes:

| Symptom | Likely cause | Fix |
|---|---|---|
| Wrong tool selected | Vague "When to use" | Add specific examples + "When NOT to use" |
| Parameter errors | Ambiguous inputs | Add format, examples, constraints |
| Hallucinations | Agent using wrong tool | Tighten negative routing in description |

> Use consistent terminology across all instructions and descriptions. If orchestration says
> "customers" but the tool description says "accounts", the agent will misbehave.
>
> Keep the total number of tools to 5–10. Smaller, focused agents with fewer tools perform
> faster and more reliably than large monolithic ones.

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
