-- Viaticos DW - quality checks for SQLite

-- 1) Basic row counts
SELECT 'dim_tiempo' AS table_name, COUNT(*) AS row_count FROM dim_tiempo
UNION ALL
SELECT 'dim_empleado', COUNT(*) FROM dim_empleado
UNION ALL
SELECT 'dim_procedimiento', COUNT(*) FROM dim_procedimiento
UNION ALL
SELECT 'dim_ruta', COUNT(*) FROM dim_ruta
UNION ALL
SELECT 'dim_fuente_dato', COUNT(*) FROM dim_fuente_dato
UNION ALL
SELECT 'fact_viaticos', COUNT(*) FROM fact_viaticos;

-- 2) Duplicate business keys in fact (must be zero)
SELECT
    commission_request_id,
    year_num,
    COUNT(*) AS duplicate_count
FROM fact_viaticos
GROUP BY commission_request_id, year_num
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, commission_request_id;

-- 3) Zero allowance records
SELECT
    year_num,
    COUNT(*) AS zero_allowance_rows,
    SUM(commission_days) AS sum_days_zero_allowance
FROM fact_viaticos
WHERE total_travel_allowance = 0
GROUP BY year_num
ORDER BY year_num;

-- 4) Date range issues and day mismatch (tolerance: 0.50 day)
WITH fact_dates AS (
    SELECT
        f.viatico_key,
        f.commission_request_id,
        f.year_num,
        f.commission_days,
        ds.full_date AS start_date,
        de.full_date AS end_date,
        (julianday(de.full_date) - julianday(ds.full_date) + 1.0) AS calendar_days
    FROM fact_viaticos f
    JOIN dim_tiempo ds ON ds.date_key = f.start_date_key
    JOIN dim_tiempo de ON de.date_key = f.end_date_key
)
SELECT
    year_num,
    SUM(CASE WHEN start_date > end_date THEN 1 ELSE 0 END) AS bad_date_order,
    SUM(CASE WHEN ABS(commission_days - calendar_days) > 0.50 THEN 1 ELSE 0 END) AS day_mismatch_rows
FROM fact_dates
GROUP BY year_num
ORDER BY year_num;

-- 5) Missing purpose category (must be zero)
SELECT
    COUNT(*) AS missing_purpose_category
FROM fact_viaticos
WHERE purpose_category IS NULL OR TRIM(purpose_category) = '';

-- 6) Distribution by source quality
SELECT
    s.reliability_label,
    f.year_num,
    COUNT(*) AS rows_count,
    SUM(f.total_travel_allowance) AS total_allowance
FROM fact_viaticos f
JOIN dim_fuente_dato s ON s.source_key = f.source_key
GROUP BY s.reliability_label, f.year_num
ORDER BY f.year_num, s.reliability_label;
