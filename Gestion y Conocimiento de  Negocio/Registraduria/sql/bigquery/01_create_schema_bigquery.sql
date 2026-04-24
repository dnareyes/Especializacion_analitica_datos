-- Viaticos DW - schema for BigQuery
-- Notes:
-- 1) Run in Standard SQL.
-- 2) This script creates dataset viaticos_dw in the active project.

CREATE SCHEMA IF NOT EXISTS viaticos_dw;

-- 1) Time dimension
CREATE TABLE IF NOT EXISTS viaticos_dw.dim_tiempo (
  date_key INT64 NOT NULL,
  full_date DATE NOT NULL,
  day_num INT64 NOT NULL,
  month_num INT64 NOT NULL,
  month_name STRING NOT NULL,
  quarter_num INT64 NOT NULL,
  year_num INT64 NOT NULL,
  week_num INT64 NOT NULL,
  is_weekend BOOL NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- 2) Employee dimension
CREATE TABLE IF NOT EXISTS viaticos_dw.dim_empleado (
  employee_key STRING NOT NULL,
  employee_id INT64 NOT NULL,
  employee_name_clean STRING NOT NULL,
  employee_position_raw STRING,
  employee_position_norm STRING,
  position_level INT64,
  is_contractor BOOL NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- 3) Procedure dimension
CREATE TABLE IF NOT EXISTS viaticos_dw.dim_procedimiento (
  procedure_key STRING NOT NULL,
  procedure_type STRING NOT NULL,
  procedure_group STRING NOT NULL,
  is_interruption BOOL NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- 4) Route dimension
CREATE TABLE IF NOT EXISTS viaticos_dw.dim_ruta (
  route_key STRING NOT NULL,
  route_original STRING NOT NULL,
  city_origin STRING,
  city_destination_main STRING,
  is_multi_destination BOOL NOT NULL,
  destination_count INT64 NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- 5) Data source dimension
CREATE TABLE IF NOT EXISTS viaticos_dw.dim_fuente_dato (
  source_key STRING NOT NULL,
  origen_register STRING NOT NULL,
  is_real_data BOOL NOT NULL,
  reliability_label STRING NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- 6) Fact table (grain: one row per commission_request_id per year)
CREATE TABLE IF NOT EXISTS viaticos_dw.fact_viaticos (
  viatico_key STRING NOT NULL,
  commission_request_id INT64 NOT NULL,
  year_num INT64 NOT NULL,
  employee_key STRING NOT NULL,
  procedure_key STRING NOT NULL,
  route_key STRING NOT NULL,
  source_key STRING NOT NULL,
  start_date_key INT64 NOT NULL,
  end_date_key INT64 NOT NULL,
  commission_days NUMERIC NOT NULL,
  total_travel_allowance NUMERIC NOT NULL,
  commission_purpose_raw STRING,
  purpose_category STRING,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY RANGE_BUCKET(year_num, GENERATE_ARRAY(2020, 2040, 1))
CLUSTER BY employee_key, procedure_key, route_key, source_key;
