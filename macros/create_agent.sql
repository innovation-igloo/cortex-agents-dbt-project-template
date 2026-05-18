{% macro create_agent(agent_name, spec_file=none) %}

  {%- set db = target.database -%}
  {%- set schema = target.schema -%}

  {%- if spec_file is none -%}
    {%- set spec_file = 'agents/' ~ agent_name ~ '.yml' -%}
  {%- endif -%}

  {%- set spec_content = load_file_contents(spec_file) -%}

  {%- if spec_content is none -%}
    {{ exceptions.raise_compiler_error(
      "Agent spec file not found: " ~ spec_file
    ) }}
  {%- endif -%}

  {% set sql %}
    CREATE OR REPLACE AGENT {{ db }}.{{ schema }}.{{ agent_name }}
      COMMENT = 'Managed by dbt - do not edit manually'
      FROM SPECIFICATION
      $$
      {{ spec_content }}
      $$
  {% endset %}

  {% do run_query(sql) %}
  {{ log("Agent created: " ~ db ~ "." ~ schema ~ "." ~ agent_name, info=True) }}

{% endmacro %}
