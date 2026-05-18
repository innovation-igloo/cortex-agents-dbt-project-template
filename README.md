# Cortex Agent Development Lifecycle with dbt Projects on Snowflake

A template dbt project for managing the full Cortex Agent lifecycle as code — semantic views, agent configurations, evaluations, and scheduling — all running natively inside Snowflake.

## Prerequisites

| Requirement | Details |
|:---|:---|
| **Snowflake Account** | Any edition with Cortex Agents enabled |
| **Role** | Must have `CREATE SEMANTIC VIEW`, `CREATE AGENT`, `CREATE TASK` on the target schema |
| **Warehouse** | Any warehouse (XS is fine for development) |
| **External Access Integration** | Required for `dbt deps` to download packages from `hub.getdbt.com` |
| **Git Repository** | Fork this repo to your own GitHub account |

### External Access Integration Setup

Run this once (requires ACCOUNTADMIN) to allow `dbt deps` to download packages:

```sql
CREATE OR REPLACE NETWORK RULE dbt_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('hub.getdbt.com', 'codeload.github.com');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION dbt_ext_access
  ALLOWED_NETWORK_RULES = (dbt_network_rule)
  ENABLED = TRUE;
```

## Quick Start: Snowflake Workspace (from Git)

1. **Fork this repository** to your GitHub account

2. **Create a Workspace** in Snowsight:
   - Navigate to **Projects > Workspaces**
   - Select **Create Workspace > From Git repository**
   - Enter your forked repo URL
   - Select your API integration (see [connecting Git to Snowflake](https://docs.snowflake.com/en/developer-guide/git/git-setting-up))

3. **Update `profiles.yml`** with your database, schema, warehouse, and role

4. **Install dependencies** — Select **Deps** from the command bar:
   - Click the dropdown arrow next to the execute button
   - Enter your External Access Integration name (e.g., `dbt_ext_access`)
   - Click **Deps**

5. **Compile** to verify — Select **Compile** from the command bar

6. **Build** — Select **Build** from the command bar to materialize models

7. **Deploy** as a DBT PROJECT object:
   - Click **Connect > Deploy dbt Project**
   - Select your target database and schema
   - Enter a name (e.g., `CORTEX_LIFECYCLE`)
   - Click **Deploy**

## Quick Start: Upload to Workspace (No Git Required)

1. **Download this template directory** to your local machine

2. **Create a blank Workspace** in Snowsight:
   - Navigate to **Projects > Workspaces**
   - Select **Create Workspace > Blank Workspace**
   - Name it (e.g., `cortex_agent_lifecycle`)

3. **Upload the template** — Click **+ Add new > Upload folder** and select the downloaded template directory

4. **Update `profiles.yml`** with your database, schema, warehouse, and role

5. **Install dependencies** — Select **Deps** from the command bar:
   - Click the dropdown arrow next to the execute button
   - Enter your External Access Integration name (e.g., `dbt_ext_access`)
   - Click **Deps**

6. **Compile** to verify — Select **Compile** from the command bar

7. **Build** — Select **Build** from the command bar to materialize models

8. **Deploy** as a DBT PROJECT object:
   - Click **Connect > Deploy dbt Project**
   - Select your target database and schema
   - Enter a name (e.g., `CORTEX_LIFECYCLE`)
   - Click **Deploy**

> **Note**: Without Git you won't have version history or PR-based review. You can connect a Git repository later via the Workspace settings to enable version control.

## Quick Start: Snowflake CLI

```bash
# Deploy
snow dbt deploy cortex_lifecycle --source . --force

# Execute
snow dbt execute cortex_lifecycle --args 'build --target dev'

# Run a specific macro
snow dbt execute cortex_lifecycle \
  --args 'run-operation create_agent --args "{agent_name: example_agent}"'
```

## Project Structure

```
├── dbt_project.yml              # Project configuration
├── packages.yml                 # dbt_semantic_view package dependency
├── profiles.yml                 # Snowflake Workspace profile (dev + prod targets)
│
├── models/
│   ├── sources.yml              # Source table definitions — start here
│   ├── staging/                 # Staging models (clean source data)
│   ├── semantic_views/
│   │   ├── _semantic_views.yml  # Model documentation
│   │   └── sv_example.sql       # Semantic view skeleton (materialized='semantic_view')
│   └── evaluations/
│       └── eval_dataset.sql     # Evaluation dataset (PARSE_JSON from seed)
│
├── macros/
│   ├── create_agent.sql         # CREATE OR REPLACE AGENT from YAML spec
│   ├── alter_agent.sql          # ALTER AGENT MODIFY LIVE VERSION from YAML spec
│   ├── create_eval_stage.sql    # Create stage + file format for eval configs
│   └── run_evaluation.sql       # Upload YAML + EXECUTE_AI_EVALUATION
│
├── agents/
│   └── example_agent.yml        # Agent specification YAML
│
├── evaluations/
│   └── example_eval_config.yml  # Evaluation configuration YAML
│
└── seeds/
    └── eval_ground_truth.csv    # Sample evaluation Q&A pairs
```

## Workflow

```
1. Define Sources ──> 2. Build Staging ──> 3. Create Semantic View ──> 4. Deploy Agent
                                                                            │
                                          6. Ship to Users <── 5. Run Evaluations
                                          (Teams / SI / MCP)       (>= 95% accuracy)
```

### Step-by-step

| Step | What | How |
|:-----|:-----|:----|
| **1** | Define source tables | Edit `models/sources.yml` with your database, schema, and table names |
| **2** | Build staging models | Create `.sql` files in `models/staging/` to clean source data |
| **3** | Create semantic view | Edit `models/semantic_views/sv_example.sql` — add TABLES, DIMENSIONS, METRICS, VERIFIED_QUERIES |
| **4** | Deploy agent | Edit `agents/example_agent.yml`, then run: `dbt run-operation create_agent --args '{agent_name: example_agent}'` |
| **5** | Run evaluation | Edit `seeds/eval_ground_truth.csv` + `evaluations/example_eval_config.yml`, upload config to stage, then run: `dbt run-operation run_evaluation --args '{agent_name: example_agent, run_name: v1, config_file: example_eval_config.yml}'` |
| **6** | Schedule | Create a Snowflake Task (see below) |

### Scheduling with Snowflake Tasks

```sql
-- Schedule daily builds
CREATE OR REPLACE TASK daily_cortex_build
  WAREHOUSE = ANALYTICS_WH
  SCHEDULE = 'USING CRON 0 6 * * * America/Denver'
AS
  EXECUTE DBT PROJECT DEV_DB.CORTEX_AGENTS.CORTEX_LIFECYCLE
    ARGS='build --target prod';

ALTER TASK daily_cortex_build RESUME;

-- Schedule daily evaluation
CREATE OR REPLACE TASK daily_agent_evaluation
  WAREHOUSE = ANALYTICS_WH
  AFTER daily_cortex_build
AS
  EXECUTE DBT PROJECT DEV_DB.CORTEX_AGENTS.CORTEX_LIFECYCLE
    ARGS='run-operation run_evaluation --args "{agent_name: example_agent, run_name: daily, config_file: example_eval_config.yml}"';

ALTER TASK daily_agent_evaluation RESUME;
```

## Macros Reference

| Macro | Purpose | Usage |
|:------|:--------|:------|
| `create_agent` | Creates or replaces a Cortex Agent from a YAML spec file | `dbt run-operation create_agent --args '{agent_name: example_agent}'` |
| `alter_agent` | Updates a live agent's specification (zero-downtime) | `dbt run-operation alter_agent --args '{agent_name: example_agent}'` |
| `create_eval_stage` | Creates the stage and file format required for evaluation configs | `dbt run-operation create_eval_stage` |
| `run_evaluation` | Creates the stage (if needed) and starts an evaluation run | `dbt run-operation run_evaluation --args '{agent_name: example_agent, run_name: v1, config_file: example_eval_config.yml}'` |

## Customization

### Adding a new semantic view
1. Create a new `.sql` file in `models/semantic_views/`
2. Use `{{ config(materialized='semantic_view') }}` at the top
3. Reference tables with `{{ source() }}` or `{{ ref() }}`
4. Run `dbt build --select my_new_sv`

### Adding a new agent
1. Create a new `.yml` file in `agents/`
2. Define the full agent spec (models, instructions, tools, tool_resources)
3. Run `dbt run-operation create_agent --args '{agent_name: my_new_agent}'`

### Adding evaluation data
1. Add rows to `seeds/eval_ground_truth.csv`
2. Run `dbt seed` to reload
3. Run `dbt run --select eval_dataset` to rebuild the evaluation table

## Resources

- [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [dbt_semantic_view Package](https://hub.getdbt.com/Snowflake-Labs/dbt_semantic_view/latest/)
- [CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [CREATE AGENT](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
- [Cortex Agent Evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
- [EXECUTE DBT PROJECT](https://docs.snowflake.com/en/sql-reference/sql/execute-dbt-project)
- [Snowflake Workspaces](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-using-workspaces)
