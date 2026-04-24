-- Viaticos DW - load from CSV in GCS for BigQuery
-- IMPORTANT: replace the URI below with your real bucket/object.
-- Example: gs://mi-bucket/Viaticos_Registraduria_2022_2025.csv

CREATE OR REPLACE EXTERNAL TABLE viaticos_dw.stg_viaticos_raw (
  commission_request_id STRING,
  procedure_type STRING,
  employee_id STRING,
  employee_name STRING,
  employee_position STRING,
  commission_days STRING,
  route STRING,
  start_date STRING,
  end_date STRING,
  total_travel_allowance STRING,
  commission_purpose STRING,
  year STRING,
  origen_register STRING
)
OPTIONS (
  format = 'CSV',
  uris = ['gs://REEMPLAZAR_BUCKET/Viaticos_Registraduria_2022_2025.csv'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

CREATE OR REPLACE TABLE viaticos_dw.stg_viaticos_normalized AS
WITH base AS (
  SELECT
    SAFE_CAST(NULLIF(REGEXP_REPLACE(TRIM(commission_request_id), r'[^0-9]', ''), '') AS INT64) AS commission_request_id,
    CASE
      WHEN LOWER(TRIM(procedure_type)) = 'prorroga' THEN 'Prorroga'
      WHEN LOWER(TRIM(procedure_type)) = 'interrumpir' THEN 'Interrumpir'
      ELSE 'Inicial'
    END AS procedure_type_norm,
    SAFE_CAST(NULLIF(REGEXP_REPLACE(TRIM(employee_id), r'[^0-9]', ''), '') AS INT64) AS employee_id,
    REGEXP_REPLACE(TRIM(COALESCE(employee_name, '')), r'\s+', ' ') AS employee_name_clean,
    NULLIF(TRIM(employee_position), '') AS employee_position_raw,
    REGEXP_REPLACE(TRIM(COALESCE(route, '')), r'\s+', ' ') AS route_original,
    CASE
      WHEN REGEXP_CONTAINS(start_date, r'^[0-9]{2}/[0-9]{2}/[0-9]{4}$')
        THEN SAFE_CAST(CONCAT(SUBSTR(start_date, 7, 4), '-', SUBSTR(start_date, 4, 2), '-', SUBSTR(start_date, 1, 2)) AS DATE)
      ELSE NULL
    END AS start_date_dt,
    CASE
      WHEN REGEXP_CONTAINS(end_date, r'^[0-9]{2}/[0-9]{2}/[0-9]{4}$')
        THEN SAFE_CAST(CONCAT(SUBSTR(end_date, 7, 4), '-', SUBSTR(end_date, 4, 2), '-', SUBSTR(end_date, 1, 2)) AS DATE)
      ELSE NULL
    END AS end_date_dt,
    NULLIF(TRIM(commission_days), '') AS commission_days_raw,
    NULLIF(TRIM(total_travel_allowance), '') AS allowance_raw,
    NULLIF(TRIM(commission_purpose), '') AS commission_purpose_raw,
    SAFE_CAST(NULLIF(REGEXP_REPLACE(TRIM(year), r'[^0-9]', ''), '') AS INT64) AS year_num,
    NULLIF(TRIM(origen_register), '') AS origen_register
  FROM viaticos_dw.stg_viaticos_raw
),
measures AS (
  SELECT
    b.*,
    COALESCE(
      CASE
        WHEN REGEXP_CONTAINS(b.commission_days_raw, r'^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$')
          THEN SAFE_CAST(REPLACE(b.commission_days_raw, ',', '') AS NUMERIC)
        WHEN REGEXP_CONTAINS(b.commission_days_raw, r'^[0-9]+,[0-9]+$')
          THEN SAFE_CAST(REPLACE(b.commission_days_raw, ',', '.') AS NUMERIC)
        ELSE SAFE_CAST(REGEXP_REPLACE(COALESCE(b.commission_days_raw, ''), r'[^0-9,\.\-]', '') AS NUMERIC)
      END,
      0
    ) AS commission_days_num,
    COALESCE(
      CASE
        WHEN REGEXP_CONTAINS(b.allowance_raw, r'^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$')
          THEN SAFE_CAST(REPLACE(b.allowance_raw, ',', '') AS NUMERIC)
        WHEN REGEXP_CONTAINS(b.allowance_raw, r'^[0-9]+,[0-9]+$')
          THEN SAFE_CAST(REPLACE(b.allowance_raw, ',', '.') AS NUMERIC)
        ELSE SAFE_CAST(REGEXP_REPLACE(COALESCE(b.allowance_raw, ''), r'[^0-9,\.\-]', '') AS NUMERIC)
      END,
      0
    ) AS total_travel_allowance_num
  FROM base b
),
routes AS (
  SELECT
    m.*,
    SPLIT(REGEXP_REPLACE(m.route_original, r'\s*[,;]\s*', ','), ',')[SAFE_OFFSET(0)] AS first_leg,
    REGEXP_CONTAINS(m.route_original, r'[,;]') AS is_multi_destination,
    GREATEST(1, ARRAY_LENGTH(SPLIT(REGEXP_REPLACE(m.route_original, r'\s*[,;]\s*', ','), ','))) AS destination_count
  FROM measures m
)
SELECT
  r.commission_request_id,
  r.procedure_type_norm,
  r.employee_id,
  r.employee_name_clean,
  r.employee_position_raw,
  r.route_original,
  NULLIF(TRIM(SPLIT(r.first_leg, '-')[SAFE_OFFSET(0)]), '') AS city_origin,
  NULLIF(TRIM(SPLIT(r.first_leg, '-')[SAFE_OFFSET(1)]), '') AS city_destination_main,
  r.is_multi_destination,
  r.destination_count,
  r.start_date_dt,
  r.end_date_dt,
  r.commission_days_num,
  r.total_travel_allowance_num,
  r.commission_purpose_raw,
  CASE
    WHEN LOWER(COALESCE(r.commission_purpose_raw, '')) LIKE '%auditor%' THEN 'AUDITORIA'
    WHEN LOWER(COALESCE(r.commission_purpose_raw, '')) LIKE '%visita%' THEN 'VISITA'
    WHEN LOWER(COALESCE(r.commission_purpose_raw, '')) LIKE '%capacit%' THEN 'CAPACITACION'
    WHEN LOWER(COALESCE(r.commission_purpose_raw, '')) LIKE '%dialogo%' THEN 'DIALOGO'
    WHEN LOWER(COALESCE(r.commission_purpose_raw, '')) LIKE '%apoyo%' THEN 'APOYO'
    ELSE 'OTROS'
  END AS purpose_category,
  r.year_num,
  r.origen_register
FROM routes r;

MERGE viaticos_dw.dim_fuente_dato t
USING (
  SELECT DISTINCT
    TO_HEX(SHA256(origen_register)) AS source_key,
    origen_register,
    CASE
      WHEN LOWER(origen_register) LIKE '%real%' AND LOWER(origen_register) NOT LIKE '%ficticio%' THEN TRUE
      ELSE FALSE
    END AS is_real_data,
    CASE
      WHEN LOWER(origen_register) LIKE '%real%' AND LOWER(origen_register) NOT LIKE '%ficticio%' THEN 'real'
      ELSE 'synthetic'
    END AS reliability_label
  FROM viaticos_dw.stg_viaticos_normalized
  WHERE origen_register IS NOT NULL
) s
ON t.origen_register = s.origen_register
WHEN MATCHED THEN UPDATE SET
  source_key = s.source_key,
  is_real_data = s.is_real_data,
  reliability_label = s.reliability_label
WHEN NOT MATCHED THEN
  INSERT (source_key, origen_register, is_real_data, reliability_label)
  VALUES (s.source_key, s.origen_register, s.is_real_data, s.reliability_label);

MERGE viaticos_dw.dim_procedimiento t
USING (
  SELECT DISTINCT
    TO_HEX(SHA256(procedure_type_norm)) AS procedure_key,
    procedure_type_norm AS procedure_type,
    CASE
      WHEN procedure_type_norm = 'Interrumpir' THEN 'Interrupcion'
      WHEN procedure_type_norm = 'Prorroga' THEN 'Extension'
      ELSE 'Normal'
    END AS procedure_group,
    procedure_type_norm = 'Interrumpir' AS is_interruption
  FROM viaticos_dw.stg_viaticos_normalized
  WHERE procedure_type_norm IS NOT NULL
) s
ON t.procedure_type = s.procedure_type
WHEN MATCHED THEN UPDATE SET
  procedure_key = s.procedure_key,
  procedure_group = s.procedure_group,
  is_interruption = s.is_interruption
WHEN NOT MATCHED THEN
  INSERT (procedure_key, procedure_type, procedure_group, is_interruption)
  VALUES (s.procedure_key, s.procedure_type, s.procedure_group, s.is_interruption);

MERGE viaticos_dw.dim_empleado t
USING (
  SELECT
    TO_HEX(SHA256(CAST(employee_id AS STRING))) AS employee_key,
    employee_id,
    MAX(employee_name_clean) AS employee_name_clean,
    MAX(employee_position_raw) AS employee_position_raw,
    CASE
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%contratista%' THEN 'CONTRATISTA'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%contralor%' THEN 'CONTRALOR'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%director%' THEN 'DIRECTOR'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%gerente%' THEN 'GERENTE'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%asesor%' THEN 'ASESOR'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%profesional%' THEN 'PROFESIONAL'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%especializado%' THEN 'ESPECIALIZADO'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%tecnologo%' THEN 'TECNOLOGO'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%tecnico%' THEN 'TECNICO'
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%auxiliar%' THEN 'AUXILIAR'
      ELSE 'OTRO'
    END AS employee_position_norm,
    CASE
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%contralor%' THEN 1
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%director%'
        OR LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%gerente%' THEN 2
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%asesor%'
        OR LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%profesional%'
        OR LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%especializado%' THEN 3
      WHEN LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%tecnologo%'
        OR LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%tecnico%'
        OR LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%auxiliar%' THEN 4
      ELSE NULL
    END AS position_level,
    LOWER(MAX(COALESCE(employee_position_raw, ''))) LIKE '%contratista%' AS is_contractor
  FROM viaticos_dw.stg_viaticos_normalized
  WHERE employee_id IS NOT NULL
  GROUP BY employee_id
) s
ON t.employee_id = s.employee_id
WHEN MATCHED THEN UPDATE SET
  employee_key = s.employee_key,
  employee_name_clean = s.employee_name_clean,
  employee_position_raw = s.employee_position_raw,
  employee_position_norm = s.employee_position_norm,
  position_level = s.position_level,
  is_contractor = s.is_contractor
WHEN NOT MATCHED THEN
  INSERT (
    employee_key,
    employee_id,
    employee_name_clean,
    employee_position_raw,
    employee_position_norm,
    position_level,
    is_contractor
  )
  VALUES (
    s.employee_key,
    s.employee_id,
    s.employee_name_clean,
    s.employee_position_raw,
    s.employee_position_norm,
    s.position_level,
    s.is_contractor
  );

MERGE viaticos_dw.dim_ruta t
USING (
  SELECT DISTINCT
    TO_HEX(SHA256(route_original)) AS route_key,
    route_original,
    city_origin,
    city_destination_main,
    is_multi_destination,
    destination_count
  FROM viaticos_dw.stg_viaticos_normalized
  WHERE route_original IS NOT NULL AND route_original <> ''
) s
ON t.route_original = s.route_original
WHEN MATCHED THEN UPDATE SET
  route_key = s.route_key,
  city_origin = s.city_origin,
  city_destination_main = s.city_destination_main,
  is_multi_destination = s.is_multi_destination,
  destination_count = s.destination_count
WHEN NOT MATCHED THEN
  INSERT (
    route_key,
    route_original,
    city_origin,
    city_destination_main,
    is_multi_destination,
    destination_count
  )
  VALUES (
    s.route_key,
    s.route_original,
    s.city_origin,
    s.city_destination_main,
    s.is_multi_destination,
    s.destination_count
  );

CREATE OR REPLACE TABLE viaticos_dw.dim_tiempo AS
WITH date_pool AS (
  SELECT start_date_dt AS dt FROM viaticos_dw.stg_viaticos_normalized WHERE start_date_dt IS NOT NULL
  UNION ALL
  SELECT end_date_dt AS dt FROM viaticos_dw.stg_viaticos_normalized WHERE end_date_dt IS NOT NULL
),
limits AS (
  SELECT MIN(dt) AS min_dt, MAX(dt) AS max_dt FROM date_pool
),
dates AS (
  SELECT dt
  FROM limits,
  UNNEST(GENERATE_DATE_ARRAY(min_dt, max_dt)) AS dt
)
SELECT
  (EXTRACT(YEAR FROM dt) * 10000 + EXTRACT(MONTH FROM dt) * 100 + EXTRACT(DAY FROM dt)) AS date_key,
  dt AS full_date,
  EXTRACT(DAY FROM dt) AS day_num,
  EXTRACT(MONTH FROM dt) AS month_num,
  CASE EXTRACT(MONTH FROM dt)
    WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March'
    WHEN 4 THEN 'April' WHEN 5 THEN 'May' WHEN 6 THEN 'June'
    WHEN 7 THEN 'July' WHEN 8 THEN 'August' WHEN 9 THEN 'September'
    WHEN 10 THEN 'October' WHEN 11 THEN 'November' ELSE 'December'
  END AS month_name,
  EXTRACT(QUARTER FROM dt) AS quarter_num,
  EXTRACT(YEAR FROM dt) AS year_num,
  EXTRACT(ISOWEEK FROM dt) AS week_num,
  EXTRACT(DAYOFWEEK FROM dt) IN (1, 7) AS is_weekend,
  CURRENT_TIMESTAMP() AS created_at
FROM dates;

MERGE viaticos_dw.fact_viaticos t
USING (
  WITH ranked AS (
    SELECT
      n.*,
      ROW_NUMBER() OVER (
        PARTITION BY n.commission_request_id, COALESCE(n.year_num, EXTRACT(YEAR FROM n.start_date_dt))
        ORDER BY n.end_date_dt DESC, n.start_date_dt DESC
      ) AS rn
    FROM viaticos_dw.stg_viaticos_normalized n
    WHERE n.commission_request_id IS NOT NULL
      AND n.employee_id IS NOT NULL
      AND n.procedure_type_norm IS NOT NULL
      AND n.route_original IS NOT NULL
      AND n.route_original <> ''
      AND n.start_date_dt IS NOT NULL
      AND n.end_date_dt IS NOT NULL
      AND n.start_date_dt <= n.end_date_dt
  )
  SELECT
    TO_HEX(SHA256(CONCAT(CAST(r.commission_request_id AS STRING), '-', CAST(COALESCE(r.year_num, EXTRACT(YEAR FROM r.start_date_dt)) AS STRING)))) AS viatico_key,
    r.commission_request_id,
    COALESCE(r.year_num, EXTRACT(YEAR FROM r.start_date_dt)) AS year_num,
    de.employee_key,
    dp.procedure_key,
    dr.route_key,
    ds.source_key,
    (EXTRACT(YEAR FROM r.start_date_dt) * 10000 + EXTRACT(MONTH FROM r.start_date_dt) * 100 + EXTRACT(DAY FROM r.start_date_dt)) AS start_date_key,
    (EXTRACT(YEAR FROM r.end_date_dt) * 10000 + EXTRACT(MONTH FROM r.end_date_dt) * 100 + EXTRACT(DAY FROM r.end_date_dt)) AS end_date_key,
    CAST(r.commission_days_num AS NUMERIC) AS commission_days,
    CAST(r.total_travel_allowance_num AS NUMERIC) AS total_travel_allowance,
    r.commission_purpose_raw,
    r.purpose_category
  FROM ranked r
  JOIN viaticos_dw.dim_empleado de
    ON de.employee_id = r.employee_id
  JOIN viaticos_dw.dim_procedimiento dp
    ON dp.procedure_type = r.procedure_type_norm
  JOIN viaticos_dw.dim_ruta dr
    ON dr.route_original = r.route_original
  JOIN viaticos_dw.dim_fuente_dato ds
    ON ds.origen_register = r.origen_register
  WHERE r.rn = 1
) s
ON t.commission_request_id = s.commission_request_id
AND t.year_num = s.year_num
WHEN MATCHED THEN UPDATE SET
  viatico_key = s.viatico_key,
  employee_key = s.employee_key,
  procedure_key = s.procedure_key,
  route_key = s.route_key,
  source_key = s.source_key,
  start_date_key = s.start_date_key,
  end_date_key = s.end_date_key,
  commission_days = s.commission_days,
  total_travel_allowance = s.total_travel_allowance,
  commission_purpose_raw = s.commission_purpose_raw,
  purpose_category = s.purpose_category
WHEN NOT MATCHED THEN
  INSERT (
    viatico_key,
    commission_request_id,
    year_num,
    employee_key,
    procedure_key,
    route_key,
    source_key,
    start_date_key,
    end_date_key,
    commission_days,
    total_travel_allowance,
    commission_purpose_raw,
    purpose_category
  )
  VALUES (
    s.viatico_key,
    s.commission_request_id,
    s.year_num,
    s.employee_key,
    s.procedure_key,
    s.route_key,
    s.source_key,
    s.start_date_key,
    s.end_date_key,
    s.commission_days,
    s.total_travel_allowance,
    s.commission_purpose_raw,
    s.purpose_category
  );
