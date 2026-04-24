# Implementacion equivalente en BigQuery y generacion directa en SQLite

## 1) BigQuery (equivalente al modelo de 6 tablas)

Archivos:

- sql/bigquery/01_create_schema_bigquery.sql
- sql/bigquery/02_load_from_gcs_bigquery.sql
- sql/bigquery/03_quality_checks_bigquery.sql
- sql/bigquery/04_analysis_queries_bigquery.sql
- sql/bigquery/run_bigquery.ps1

### Prerrequisitos BigQuery

- Google Cloud CLI instalado (comandos gcloud, bq y gsutil disponibles).
- Proyecto activo y autenticacion listos con gcloud init.
- CSV cargado en GCS.

### Flujo recomendado

1. Crear dataset y tablas:

```sql
-- Ejecutar archivo
sql/bigquery/01_create_schema_bigquery.sql
```

2. Cargar datos desde CSV en GCS y poblar dimensiones/fact:

- En sql/bigquery/02_load_from_gcs_bigquery.sql cambia:
  - gs://REEMPLAZAR_BUCKET/Viaticos_Registraduria_2022_2025.csv

```sql
-- Ejecutar archivo
sql/bigquery/02_load_from_gcs_bigquery.sql
```

3. Validar calidad:

```sql
-- Ejecutar archivo
sql/bigquery/03_quality_checks_bigquery.sql
```

4. Ejecutar analitica base:

```sql
-- Ejecutar archivo
sql/bigquery/04_analysis_queries_bigquery.sql
```

### Opcion automatizada (PowerShell)

Si ya tienes gcloud y bq configurados, puedes ejecutar todo en orden con un solo comando:

```powershell
./sql/bigquery/run_bigquery.ps1 -ProjectId "<tu_project_id>" -GcsCsvUri "gs://<tu_bucket>/Viaticos_Registraduria_2022_2025.csv" -Location "US"
```

### Notas BigQuery

- El esquema mantiene 6 tablas (1 fact + 5 dimensiones).
- Las claves de dimensiones se generan de forma deterministica con SHA256.
- La fact usa MERGE por llave de negocio (commission_request_id, year_num).
- Si prefieres, se puede reemplazar la tabla externa por una tabla nativa de staging con bq load.

## 2) SQLite (generacion directa desde CSV)

Nota de comportamiento actual en SQLite:

- fact_viaticos conserva todas las filas del CSV origen (sin deduplicacion por llave de negocio).
- Las novedades de calidad se guardan en la columna quality_note en lugar de descartar filas.

Archivos:

- sqlite/generate_sqlite_dw.py
- sqlite/export_sqlite_tables_to_csv.py
- sqlite/run_build_sqlite.ps1
- sqlite/run_all_sqlite.ps1
- sqlite/quality_checks_sqlite.sql
- sqlite/analysis_queries_sqlite.sql

### Opcion A: comando directo Python

Desde la raiz del proyecto:

```powershell
python ./sqlite/generate_sqlite_dw.py --csv "./Viaticos_Registraduria_2022_2025.csv" --db "./sqlite/viaticos_dw.sqlite" --overwrite
```

### Opcion B: wrapper PowerShell

```powershell
./sqlite/run_build_sqlite.ps1 -CsvPath "./Viaticos_Registraduria_2022_2025.csv" -DbPath "./sqlite/viaticos_dw.sqlite" -Overwrite
```

### Opcion C: un solo comando (.db y opcional 6 CSV)

Generar solo el archivo .db:

```powershell
./sqlite/run_all_sqlite.ps1 -CsvPath "./Viaticos_Registraduria_2022_2025.csv" -DbPath "./sqlite/viaticos_dw.sqlite" -Overwrite
```

Generar .db y exportar las 6 tablas en CSV:

```powershell
./sqlite/run_all_sqlite.ps1 -CsvPath "./Viaticos_Registraduria_2022_2025.csv" -DbPath "./sqlite/viaticos_dw.sqlite" -CsvOutDir "./sqlite/exports" -Overwrite -ExportCsv
```

Tambien puedes exportar CSV desde un .db ya existente:

```powershell
python ./sqlite/export_sqlite_tables_to_csv.py --db "./sqlite/viaticos_dw.sqlite" --outdir "./sqlite/exports"
```

### Verificacion en SQLite

```powershell
sqlite3 ./sqlite/viaticos_dw.sqlite ".read ./sqlite/quality_checks_sqlite.sql"
```

### Analitica en SQLite

```powershell
sqlite3 ./sqlite/viaticos_dw.sqlite ".read ./sqlite/analysis_queries_sqlite.sql"
```

### Archivos CSV esperados en sqlite/exports

- dim_tiempo.csv
- dim_empleado.csv
- dim_procedimiento.csv
- dim_ruta.csv
- dim_fuente_dato.csv
- fact_viaticos.csv

## Observaciones de diseno

- Grano de fact_viaticos en SQLite: una fila por registro de origen del CSV.
- Se conserva commission_purpose_raw para trazabilidad.
- Se agrega purpose_category para analitica tematica.
- Se separa fuente de datos real/synthetic para comparativos con confiabilidad.
- La lectura de CSV usa deteccion auto (utf-8-sig y fallback latin-1) con decodificacion estricta para preservar caracteres.
