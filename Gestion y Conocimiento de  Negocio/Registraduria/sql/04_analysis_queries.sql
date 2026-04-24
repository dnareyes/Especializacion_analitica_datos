-- Viaticos DW - starter analytics queries
-- Target engine: PostgreSQL 14+

SET search_path TO viaticos_dw, public;

-- 1) Monthly spend trend
SELECT
    t.year_num,
    t.month_num,
    SUM(f.total_travel_allowance) AS total_allowance,
    COUNT(*) AS commission_count,
    AVG(f.total_travel_allowance) AS avg_allowance
FROM fact_viaticos f
JOIN dim_tiempo t ON t.date_key = f.start_date_key
GROUP BY t.year_num, t.month_num
ORDER BY t.year_num, t.month_num;

-- 2) Top 20 employees by total spend
SELECT
    e.employee_id,
    e.employee_name_clean,
    e.employee_position_norm,
    SUM(f.total_travel_allowance) AS total_allowance,
    COUNT(*) AS commission_count,
    SUM(f.commission_days) AS total_days
FROM fact_viaticos f
JOIN dim_empleado e ON e.employee_key = f.employee_key
GROUP BY e.employee_id, e.employee_name_clean, e.employee_position_norm
ORDER BY total_allowance DESC
LIMIT 20;

-- 3) Spend by route
SELECT
    r.city_origin,
    r.city_destination_main,
    r.is_multi_destination,
    SUM(f.total_travel_allowance) AS total_allowance,
    COUNT(*) AS commission_count,
    AVG(f.total_travel_allowance) AS avg_allowance
FROM fact_viaticos f
JOIN dim_ruta r ON r.route_key = f.route_key
GROUP BY r.city_origin, r.city_destination_main, r.is_multi_destination
ORDER BY total_allowance DESC
LIMIT 50;

-- 4) Spend and efficiency by procedure type
SELECT
    p.procedure_type,
    f.year_num,
    COUNT(*) AS commission_count,
    SUM(f.total_travel_allowance) AS total_allowance,
    SUM(f.commission_days) AS total_days,
    CASE
        WHEN SUM(f.commission_days) = 0 THEN NULL
        ELSE SUM(f.total_travel_allowance) / SUM(f.commission_days)
    END AS allowance_per_day
FROM fact_viaticos f
JOIN dim_procedimiento p ON p.procedure_key = f.procedure_key
GROUP BY p.procedure_type, f.year_num
ORDER BY f.year_num, p.procedure_type;

-- 5) Real vs synthetic comparison
SELECT
    s.reliability_label,
    f.year_num,
    COUNT(*) AS commission_count,
    SUM(f.total_travel_allowance) AS total_allowance,
    AVG(f.total_travel_allowance) AS avg_allowance,
    AVG(f.commission_days) AS avg_days
FROM fact_viaticos f
JOIN dim_fuente_dato s ON s.source_key = f.source_key
GROUP BY s.reliability_label, f.year_num
ORDER BY f.year_num, s.reliability_label;

-- 6) High allowance-per-day outliers
SELECT
    f.commission_request_id,
    f.year_num,
    e.employee_name_clean,
    p.procedure_type,
    r.city_origin,
    r.city_destination_main,
    f.commission_days,
    f.total_travel_allowance,
    CASE
        WHEN f.commission_days = 0 THEN NULL
        ELSE f.total_travel_allowance / f.commission_days
    END AS allowance_per_day
FROM fact_viaticos f
JOIN dim_empleado e ON e.employee_key = f.employee_key
JOIN dim_procedimiento p ON p.procedure_key = f.procedure_key
JOIN dim_ruta r ON r.route_key = f.route_key
ORDER BY allowance_per_day DESC NULLS LAST
LIMIT 100;
