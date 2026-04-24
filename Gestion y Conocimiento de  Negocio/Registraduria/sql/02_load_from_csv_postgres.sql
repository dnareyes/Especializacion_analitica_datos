-- Viaticos DW - CSV load and normalization
-- Target engine: PostgreSQL 14+
-- Usage example (psql):
--   \set csv_path 'C:/Users/Diego Reyes/Downloads/Registraduria/Viaticos_Registraduria_2022_2025.csv'
--   \i sql/02_load_from_csv_postgres.sql

SET search_path TO viaticos_dw, public;

-- If csv_path is not provided by psql, set a default.
\if :{?csv_path}
\else
\set csv_path 'C:/Users/Diego Reyes/Downloads/Registraduria/Viaticos_Registraduria_2022_2025.csv'
\endif

DROP TABLE IF EXISTS stg_viaticos_raw;
CREATE TEMP TABLE stg_viaticos_raw (
    commission_request_id      TEXT,
    procedure_type             TEXT,
    employee_id                TEXT,
    employee_name              TEXT,
    employee_position          TEXT,
    commission_days            TEXT,
    route                      TEXT,
    start_date                 TEXT,
    end_date                   TEXT,
    total_travel_allowance     TEXT,
    commission_purpose         TEXT,
    year                       TEXT,
    origen_register            TEXT
);

COPY stg_viaticos_raw
FROM :'csv_path'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

DROP VIEW IF EXISTS v_viaticos_normalized;
CREATE TEMP VIEW v_viaticos_normalized AS
WITH base AS (
    SELECT
        NULLIF(REGEXP_REPLACE(TRIM(commission_request_id), '[^0-9]', '', 'g'), '')::BIGINT AS commission_request_id,
        CASE
            WHEN LOWER(TRIM(procedure_type)) = 'prorroga' THEN 'Prorroga'
            WHEN LOWER(TRIM(procedure_type)) = 'interrumpir' THEN 'Interrumpir'
            ELSE 'Inicial'
        END AS procedure_type_norm,
        NULLIF(REGEXP_REPLACE(TRIM(employee_id), '[^0-9]', '', 'g'), '')::BIGINT AS employee_id,
        REGEXP_REPLACE(TRIM(COALESCE(employee_name, '')), '[[:space:]]+', ' ', 'g') AS employee_name_clean,
        NULLIF(TRIM(employee_position), '') AS employee_position_raw,
        REGEXP_REPLACE(TRIM(COALESCE(route, '')), '[[:space:]]+', ' ', 'g') AS route_original,
        CASE
            WHEN start_date ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN TO_DATE(start_date, 'DD/MM/YYYY')
            ELSE NULL
        END AS start_date_dt,
        CASE
            WHEN end_date ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN TO_DATE(end_date, 'DD/MM/YYYY')
            ELSE NULL
        END AS end_date_dt,
        NULLIF(TRIM(commission_days), '') AS commission_days_raw,
        NULLIF(TRIM(total_travel_allowance), '') AS allowance_raw,
        NULLIF(TRIM(commission_purpose), '') AS commission_purpose_raw,
        NULLIF(REGEXP_REPLACE(TRIM(year), '[^0-9]', '', 'g'), '')::SMALLINT AS year_num,
        NULLIF(TRIM(origen_register), '') AS origen_register
    FROM stg_viaticos_raw
),
measures AS (
    SELECT
        b.*,
        COALESCE(
            CASE
                WHEN b.commission_days_raw ~ '^[0-9]{1,3}(,[0-9]{3})+([.][0-9]+)?$' THEN REPLACE(b.commission_days_raw, ',', '')::NUMERIC
                WHEN b.commission_days_raw ~ '^[0-9]+,[0-9]+$' THEN REPLACE(b.commission_days_raw, ',', '.')::NUMERIC
                ELSE NULLIF(REGEXP_REPLACE(b.commission_days_raw, '[^0-9,.-]', '', 'g'), '')::NUMERIC
            END,
            0::NUMERIC
        ) AS commission_days_num,
        COALESCE(
            CASE
                WHEN b.allowance_raw ~ '^[0-9]{1,3}(,[0-9]{3})+([.][0-9]+)?$' THEN REPLACE(b.allowance_raw, ',', '')::NUMERIC
                WHEN b.allowance_raw ~ '^[0-9]+,[0-9]+$' THEN REPLACE(b.allowance_raw, ',', '.')::NUMERIC
                ELSE NULLIF(REGEXP_REPLACE(b.allowance_raw, '[^0-9,.-]', '', 'g'), '')::NUMERIC
            END,
            0::NUMERIC
        ) AS total_travel_allowance_num
    FROM base b
),
routes AS (
    SELECT
        m.*,
        SPLIT_PART(REGEXP_REPLACE(m.route_original, '[[:space:]]*[,;][[:space:]]*', ',', 'g'), ',', 1) AS first_leg,
        (m.route_original ~ '[,;]') AS is_multi_destination,
        GREATEST(1, CARDINALITY(REGEXP_SPLIT_TO_ARRAY(m.route_original, '[[:space:]]*[,;][[:space:]]*')))::SMALLINT AS destination_count
    FROM measures m
)
SELECT
    r.commission_request_id,
    r.procedure_type_norm,
    r.employee_id,
    r.employee_name_clean,
    r.employee_position_raw,
    r.route_original,
    NULLIF(TRIM(SPLIT_PART(r.first_leg, '-', 1)), '') AS city_origin,
    NULLIF(TRIM(SPLIT_PART(r.first_leg, '-', 2)), '') AS city_destination_main,
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

-- Load DIM_FUENTE_DATO
INSERT INTO dim_fuente_dato (origen_register, is_real_data, reliability_label)
SELECT DISTINCT
    n.origen_register,
    CASE
        WHEN LOWER(n.origen_register) LIKE '%real%' AND LOWER(n.origen_register) NOT LIKE '%ficticio%' THEN TRUE
        ELSE FALSE
    END AS is_real_data,
    CASE
        WHEN LOWER(n.origen_register) LIKE '%real%' AND LOWER(n.origen_register) NOT LIKE '%ficticio%' THEN 'real'
        ELSE 'synthetic'
    END AS reliability_label
FROM v_viaticos_normalized n
WHERE n.origen_register IS NOT NULL
ON CONFLICT (origen_register) DO UPDATE
SET
    is_real_data = EXCLUDED.is_real_data,
    reliability_label = EXCLUDED.reliability_label;

-- Load DIM_PROCEDIMIENTO
INSERT INTO dim_procedimiento (procedure_type, procedure_group, is_interruption)
SELECT DISTINCT
    n.procedure_type_norm,
    CASE
        WHEN n.procedure_type_norm = 'Interrumpir' THEN 'Interrupcion'
        WHEN n.procedure_type_norm = 'Prorroga' THEN 'Extension'
        ELSE 'Normal'
    END AS procedure_group,
    (n.procedure_type_norm = 'Interrumpir') AS is_interruption
FROM v_viaticos_normalized n
WHERE n.procedure_type_norm IS NOT NULL
ON CONFLICT (procedure_type) DO UPDATE
SET
    procedure_group = EXCLUDED.procedure_group,
    is_interruption = EXCLUDED.is_interruption;

-- Load DIM_EMPLEADO
INSERT INTO dim_empleado (
    employee_id,
    employee_name_clean,
    employee_position_raw,
    employee_position_norm,
    position_level,
    is_contractor
)
SELECT
    n.employee_id,
    MAX(n.employee_name_clean) AS employee_name_clean,
    MAX(n.employee_position_raw) AS employee_position_raw,
    CASE
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%contratista%' THEN 'CONTRATISTA'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%contralor%' THEN 'CONTRALOR'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%director%' THEN 'DIRECTOR'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%gerente%' THEN 'GERENTE'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%asesor%' THEN 'ASESOR'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%profesional%' THEN 'PROFESIONAL'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%especializado%' THEN 'ESPECIALIZADO'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%tecnologo%' THEN 'TECNOLOGO'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%tecnico%' THEN 'TECNICO'
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%auxiliar%' THEN 'AUXILIAR'
        ELSE 'OTRO'
    END AS employee_position_norm,
    CASE
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%contralor%' THEN 1
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%director%'
          OR LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%gerente%' THEN 2
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%asesor%'
          OR LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%profesional%'
          OR LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%especializado%' THEN 3
        WHEN LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%tecnologo%'
          OR LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%tecnico%'
          OR LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%auxiliar%' THEN 4
        ELSE NULL
    END AS position_level,
    (LOWER(MAX(COALESCE(n.employee_position_raw, ''))) LIKE '%contratista%') AS is_contractor
FROM v_viaticos_normalized n
WHERE n.employee_id IS NOT NULL
GROUP BY n.employee_id
ON CONFLICT (employee_id) DO UPDATE
SET
    employee_name_clean = EXCLUDED.employee_name_clean,
    employee_position_raw = EXCLUDED.employee_position_raw,
    employee_position_norm = EXCLUDED.employee_position_norm,
    position_level = EXCLUDED.position_level,
    is_contractor = EXCLUDED.is_contractor;

-- Load DIM_RUTA
INSERT INTO dim_ruta (
    route_original,
    city_origin,
    city_destination_main,
    is_multi_destination,
    destination_count
)
SELECT DISTINCT
    n.route_original,
    n.city_origin,
    n.city_destination_main,
    n.is_multi_destination,
    n.destination_count
FROM v_viaticos_normalized n
WHERE n.route_original IS NOT NULL AND n.route_original <> ''
ON CONFLICT (route_original) DO UPDATE
SET
    city_origin = EXCLUDED.city_origin,
    city_destination_main = EXCLUDED.city_destination_main,
    is_multi_destination = EXCLUDED.is_multi_destination,
    destination_count = EXCLUDED.destination_count;

-- Load DIM_TIEMPO using min/max dates found in the source.
WITH date_pool AS (
    SELECT start_date_dt AS dt FROM v_viaticos_normalized WHERE start_date_dt IS NOT NULL
    UNION ALL
    SELECT end_date_dt AS dt FROM v_viaticos_normalized WHERE end_date_dt IS NOT NULL
),
limits AS (
    SELECT MIN(dt) AS min_dt, MAX(dt) AS max_dt FROM date_pool
)
INSERT INTO dim_tiempo (
    date_key,
    full_date,
    day_num,
    month_num,
    month_name,
    quarter_num,
    year_num,
    week_num,
    is_weekend
)
SELECT
    TO_CHAR(gs.dt::DATE, 'YYYYMMDD')::INTEGER AS date_key,
    gs.dt::DATE AS full_date,
    EXTRACT(DAY FROM gs.dt)::SMALLINT AS day_num,
    EXTRACT(MONTH FROM gs.dt)::SMALLINT AS month_num,
    TRIM(TO_CHAR(gs.dt, 'Month')) AS month_name,
    EXTRACT(QUARTER FROM gs.dt)::SMALLINT AS quarter_num,
    EXTRACT(YEAR FROM gs.dt)::SMALLINT AS year_num,
    EXTRACT(WEEK FROM gs.dt)::SMALLINT AS week_num,
    (EXTRACT(ISODOW FROM gs.dt) IN (6, 7)) AS is_weekend
FROM limits l
CROSS JOIN LATERAL GENERATE_SERIES(l.min_dt, l.max_dt, INTERVAL '1 day') AS gs(dt)
WHERE l.min_dt IS NOT NULL
ON CONFLICT (date_key) DO NOTHING;

-- Load FACT_VIATICOS
WITH ranked AS (
    SELECT
        n.*,
        ROW_NUMBER() OVER (
            PARTITION BY n.commission_request_id, COALESCE(n.year_num, EXTRACT(YEAR FROM n.start_date_dt)::SMALLINT)
            ORDER BY n.end_date_dt DESC NULLS LAST, n.start_date_dt DESC NULLS LAST
        ) AS rn
    FROM v_viaticos_normalized n
    WHERE n.commission_request_id IS NOT NULL
      AND n.employee_id IS NOT NULL
      AND n.procedure_type_norm IS NOT NULL
      AND n.route_original IS NOT NULL
      AND n.route_original <> ''
      AND n.start_date_dt IS NOT NULL
      AND n.end_date_dt IS NOT NULL
      AND n.start_date_dt <= n.end_date_dt
)
INSERT INTO fact_viaticos (
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
SELECT
    r.commission_request_id,
    COALESCE(r.year_num, EXTRACT(YEAR FROM r.start_date_dt)::SMALLINT) AS year_num,
    de.employee_key,
    dp.procedure_key,
    dr.route_key,
    ds.source_key,
    dts.date_key AS start_date_key,
    dte.date_key AS end_date_key,
    r.commission_days_num::NUMERIC(6,2) AS commission_days,
    r.total_travel_allowance_num::NUMERIC(14,2) AS total_travel_allowance,
    r.commission_purpose_raw,
    r.purpose_category
FROM ranked r
JOIN dim_empleado de
    ON de.employee_id = r.employee_id
JOIN dim_procedimiento dp
    ON dp.procedure_type = r.procedure_type_norm
JOIN dim_ruta dr
    ON dr.route_original = r.route_original
JOIN dim_fuente_dato ds
    ON ds.origen_register = r.origen_register
JOIN dim_tiempo dts
    ON dts.full_date = r.start_date_dt
JOIN dim_tiempo dte
    ON dte.full_date = r.end_date_dt
WHERE r.rn = 1
ON CONFLICT (commission_request_id, year_num) DO UPDATE
SET
    employee_key = EXCLUDED.employee_key,
    procedure_key = EXCLUDED.procedure_key,
    route_key = EXCLUDED.route_key,
    source_key = EXCLUDED.source_key,
    start_date_key = EXCLUDED.start_date_key,
    end_date_key = EXCLUDED.end_date_key,
    commission_days = EXCLUDED.commission_days,
    total_travel_allowance = EXCLUDED.total_travel_allowance,
    commission_purpose_raw = EXCLUDED.commission_purpose_raw,
    purpose_category = EXCLUDED.purpose_category;
