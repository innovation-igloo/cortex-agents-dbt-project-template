{{ config(materialized='semantic_view') }}

-- =============================================================================
-- Semantic View: sv_example
-- =============================================================================
-- TODO: Replace this skeleton with your actual semantic view definition.
-- The dbt_semantic_view package passes your SQL directly to Snowflake's
-- CREATE OR REPLACE SEMANTIC VIEW — full SQL API coverage, no package
-- upgrade needed for new Snowflake features.
--
-- Uncomment and customize the blocks below. Use {{ source() }} and {{ ref() }}
-- to reference tables so dbt handles fully-qualified name resolution.
-- =============================================================================

TABLES (
  -- TODO: Define your logical tables with primary keys.
  -- Example:
  -- orders AS {{ source('raw', 'orders') }}
  --   PRIMARY KEY (order_id)
  --   COMMENT = 'Customer orders with fulfillment status',
  --
  -- products AS {{ ref('stg_products') }}
  --   PRIMARY KEY (product_id)
  --   COMMENT = 'Product catalog with inventory data'

  placeholder AS {{ source('raw', 'placeholder_table') }}
    PRIMARY KEY (id)
    COMMENT = 'TODO: Replace with your first table'
)

-- RELATIONSHIPS (
--   -- TODO: Define foreign key relationships between tables.
--   -- Example:
--   -- orders_to_products AS
--   --   orders (product_id) REFERENCES products
-- )

-- DIMENSIONS (
--   -- TODO: Define dimensions users will filter and group by.
--   -- Example:
--   -- products.product_name AS product_name
--   --   COMMENT = 'Product display name'
--   --   WITH SYNONYMS = ('item name', 'sku name'),
--   --
--   -- orders.order_date AS order_date
--   --   COMMENT = 'Date the order was placed'
-- )

-- METRICS (
--   -- TODO: Define aggregate metrics users will ask about.
--   -- Example:
--   -- orders.total_revenue AS SUM(order_total)
--   --   COMMENT = 'Total revenue from orders',
--   --
--   -- orders.order_count AS COUNT(order_id)
--   --   COMMENT = 'Number of orders placed'
-- )

-- AI_SQL_GENERATION
--   'TODO: Add business-specific SQL generation rules here.
--    Example: Default to the most recent date if no date is specified.
--    Always round currency values to 2 decimal places.'

-- AI_QUESTION_CATEGORIZATION
--   'TODO: Add guardrails for out-of-scope questions here.
--    Example: Reject questions about employee data or HR topics.'

-- AI_VERIFIED_QUERIES (
--   -- TODO: Add verified query pairs for common questions.
--   -- Example:
--   -- top_products AS (
--   --   QUESTION 'What are the top selling products?'
--   --   VERIFIED_AT 1747267200
--   --   ONBOARDING_QUESTION TRUE
--   --   SQL 'SELECT product_name, total_revenue
--   --        FROM SEMANTIC_VIEW(sv_example
--   --          DIMENSIONS products.product_name
--   --          METRICS orders.total_revenue)
--   --        ORDER BY total_revenue DESC
--   --        LIMIT 10'
--   -- )
-- )
