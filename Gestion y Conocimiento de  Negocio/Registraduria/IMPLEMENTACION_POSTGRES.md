# Implementacion inicial - Viaticos DW (PostgreSQL)

Este paquete crea un modelo analitico de 6 tablas (1 fact + 5 dimensiones) y carga el CSV de viaticos.

## Archivos

- sql/00_run_all_postgres.sql
- sql/01_create_schema_postgres.sql
- sql/02_load_from_csv_postgres.sql
- sql/03_quality_checks.sql
- sql/04_analysis_queries.sql

## Modelo (6 tablas)

1. dim_tiempo
2. dim_empleado
3. dim_procedimiento
4. dim_ruta
5. dim_fuente_dato
6. fact_viaticos

## Prerrequisitos

- PostgreSQL 14+
- psql en PATH

## Ejecucion rapida

Desde la carpeta del proyecto:

```powershell
psql -h <host> -p <port> -U <usuario> -d <base_datos> -v csv_path='C:/Users/Diego Reyes/Downloads/Registraduria/Viaticos_Registraduria_2022_2025.csv' -f sql/00_run_all_postgres.sql
```

Si ya estas dentro de psql:

```sql
\set csv_path 'C:/Users/Diego Reyes/Downloads/Registraduria/Viaticos_Registraduria_2022_2025.csv'
\i sql/00_run_all_postgres.sql
```

## Ejecucion por fases

1. Crear esquema:

```sql
\i sql/01_create_schema_postgres.sql
```

2. Cargar CSV y poblar dimensiones/fact:

```sql
\set csv_path 'C:/Users/Diego Reyes/Downloads/Registraduria/Viaticos_Registraduria_2022_2025.csv'
\i sql/02_load_from_csv_postgres.sql
```

3. Validar calidad:

```sql
\i sql/03_quality_checks.sql
```

4. Correr analitica base:

```sql
\i sql/04_analysis_queries.sql
```

## Notas de diseno

- Grano de fact_viaticos: una fila por commission_request_id por anio.
- La carga es idempotente (usa upsert) para facilitar recargas.
- Registros con fechas invalidas o claves incompletas se excluyen de la fact.
- Se conserva commission_purpose_raw para trazabilidad y se agrega purpose_category para analitica.
