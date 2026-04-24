-- Run full setup for Viaticos DW (PostgreSQL 14+)

-- Optional before running:
--   \set csv_path 'C:/Users/Diego Reyes/Downloads/Registraduria/Viaticos_Registraduria_2022_2025.csv'

\i sql/01_create_schema_postgres.sql
\i sql/02_load_from_csv_postgres.sql
\i sql/03_quality_checks.sql
