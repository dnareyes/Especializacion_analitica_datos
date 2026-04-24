-- Viaticos DW - base schema (6 tables)
-- Target engine: PostgreSQL 14+

CREATE SCHEMA IF NOT EXISTS viaticos_dw;
SET search_path TO viaticos_dw, public;

-- 1) Time dimension
CREATE TABLE IF NOT EXISTS dim_tiempo (
    date_key            INTEGER PRIMARY KEY,
    full_date           DATE NOT NULL UNIQUE,
    day_num             SMALLINT NOT NULL,
    month_num           SMALLINT NOT NULL,
    month_name          VARCHAR(15) NOT NULL,
    quarter_num         SMALLINT NOT NULL,
    year_num            SMALLINT NOT NULL,
    week_num            SMALLINT NOT NULL,
    is_weekend          BOOLEAN NOT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_dim_tiempo_month CHECK (month_num BETWEEN 1 AND 12),
    CONSTRAINT ck_dim_tiempo_day CHECK (day_num BETWEEN 1 AND 31)
);

-- 2) Employee dimension
CREATE TABLE IF NOT EXISTS dim_empleado (
    employee_key            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id             BIGINT NOT NULL UNIQUE,
    employee_name_clean     VARCHAR(200) NOT NULL,
    employee_position_raw   VARCHAR(200),
    employee_position_norm  VARCHAR(100),
    position_level          SMALLINT,
    is_contractor           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 3) Procedure dimension
CREATE TABLE IF NOT EXISTS dim_procedimiento (
    procedure_key       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    procedure_type      VARCHAR(50) NOT NULL UNIQUE,
    procedure_group     VARCHAR(50) NOT NULL,
    is_interruption     BOOLEAN NOT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 4) Route dimension
CREATE TABLE IF NOT EXISTS dim_ruta (
    route_key               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    route_original          TEXT NOT NULL UNIQUE,
    city_origin             VARCHAR(120),
    city_destination_main   VARCHAR(120),
    is_multi_destination    BOOLEAN NOT NULL,
    destination_count       SMALLINT NOT NULL,
    created_at              TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_dim_ruta_destination_count CHECK (destination_count >= 1)
);

-- 5) Data source dimension
CREATE TABLE IF NOT EXISTS dim_fuente_dato (
    source_key          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    origen_register     VARCHAR(200) NOT NULL UNIQUE,
    is_real_data        BOOLEAN NOT NULL,
    reliability_label   VARCHAR(20) NOT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 6) Facts table (grain: one row per commission_request_id per year)
CREATE TABLE IF NOT EXISTS fact_viaticos (
    viatico_key              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    commission_request_id    BIGINT NOT NULL,
    year_num                 SMALLINT NOT NULL,
    employee_key             BIGINT NOT NULL,
    procedure_key            INTEGER NOT NULL,
    route_key                BIGINT NOT NULL,
    source_key               INTEGER NOT NULL,
    start_date_key           INTEGER NOT NULL,
    end_date_key             INTEGER NOT NULL,
    commission_days          NUMERIC(6,2) NOT NULL,
    total_travel_allowance   NUMERIC(14,2) NOT NULL,
    commission_purpose_raw   TEXT,
    purpose_category         VARCHAR(80),
    created_at               TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_fact_business UNIQUE (commission_request_id, year_num),
    CONSTRAINT ck_fact_days_non_negative CHECK (commission_days >= 0),
    CONSTRAINT ck_fact_allowance_non_negative CHECK (total_travel_allowance >= 0),
    CONSTRAINT ck_fact_date_range CHECK (start_date_key <= end_date_key),
    CONSTRAINT fk_fact_employee FOREIGN KEY (employee_key) REFERENCES dim_empleado(employee_key),
    CONSTRAINT fk_fact_procedure FOREIGN KEY (procedure_key) REFERENCES dim_procedimiento(procedure_key),
    CONSTRAINT fk_fact_route FOREIGN KEY (route_key) REFERENCES dim_ruta(route_key),
    CONSTRAINT fk_fact_source FOREIGN KEY (source_key) REFERENCES dim_fuente_dato(source_key),
    CONSTRAINT fk_fact_start_date FOREIGN KEY (start_date_key) REFERENCES dim_tiempo(date_key),
    CONSTRAINT fk_fact_end_date FOREIGN KEY (end_date_key) REFERENCES dim_tiempo(date_key)
);

CREATE INDEX IF NOT EXISTS ix_fact_viaticos_year ON fact_viaticos(year_num);
CREATE INDEX IF NOT EXISTS ix_fact_viaticos_employee ON fact_viaticos(employee_key);
CREATE INDEX IF NOT EXISTS ix_fact_viaticos_procedure ON fact_viaticos(procedure_key);
CREATE INDEX IF NOT EXISTS ix_fact_viaticos_route ON fact_viaticos(route_key);
CREATE INDEX IF NOT EXISTS ix_fact_viaticos_source ON fact_viaticos(source_key);
CREATE INDEX IF NOT EXISTS ix_fact_viaticos_start_date ON fact_viaticos(start_date_key);
CREATE INDEX IF NOT EXISTS ix_fact_viaticos_end_date ON fact_viaticos(end_date_key);
