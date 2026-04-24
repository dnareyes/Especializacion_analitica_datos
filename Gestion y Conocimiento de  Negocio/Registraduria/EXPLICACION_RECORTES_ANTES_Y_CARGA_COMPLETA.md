# Explicacion de recortes anteriores y carga completa actual

## Contexto

Este documento resume dos estados del pipeline de carga:

1. Antes: modelo con filtros y deduplicacion en fact_viaticos.
2. Ahora: modelo que conserva todos los registros del CSV en fact_viaticos.

## Antes (por que quedaban menos filas)

Con la logica anterior, el flujo hacia dos recortes:

1. Filtro de calidad:
   - Se descartaban filas con start_date mayor que end_date.
   - Resultado: 201 filas menos.

2. Deduplicacion por llave de negocio:
   - Se consolidaba a 1 fila por (commission_request_id, year_num).
   - Resultado: 1742 filas menos.

Resumen anterior:

- CSV origen: 16001
- Candidatas validas: 15800
- Fact final deduplicada: 14058

## Ahora (conservando todos los registros)

Se cambio la carga para conservar todas las filas del CSV en fact_viaticos.

Resultado validado en la corrida actual:

- CSV origen: 16001
- Fact final: 16001
- CSV exportado fact_viaticos.csv: 16001 filas

No se elimina ninguna fila por calidad ni por deduplicacion.

## Como se conserva la calidad sin recortar

En vez de descartar registros, ahora:

1. Se registra la novedad de calidad en quality_note.
2. Se normalizan valores faltantes para permitir carga completa.
3. Se corrigen fechas invertidas para cumplir integridad de claves de tiempo.

Ejemplo validado:

- quality_note = start_date_gt_end_date: 201 filas

## Cambios tecnicos aplicados

Archivos principales modificados:

- [sqlite/generate_sqlite_dw.py](sqlite/generate_sqlite_dw.py)
  - Fact sin deduplicacion por llave.
  - Carga de todas las filas con quality_note.
  - Fallbacks para campos faltantes (empleado, ruta, origen, fechas, anio, id).

- [sqlite/run_all_sqlite.ps1](sqlite/run_all_sqlite.ps1)
  - Orquesta carga y export.

- [sqlite/export_sqlite_tables_to_csv.py](sqlite/export_sqlite_tables_to_csv.py)
  - Exporta las 6 tablas a CSV.

## Comando recomendado

Generar base y 6 CSV conservando todos los registros:

./sqlite/run_all_sqlite.ps1 -CsvPath "./Viaticos_Registraduria_2022_2025.csv" -DbPath "./sqlite/viaticos_dw.sqlite" -CsvOutDir "./sqlite/exports" -InputEncoding "auto" -OutputEncoding "latin-1" -Overwrite -ExportCsv

## Verificacion minima

1. Conteo en base:
   - SELECT COUNT(*) FROM fact_viaticos;
   - Debe dar 16001.

2. Conteo en CSV exportado:
   - fact_viaticos.csv sin encabezado debe tener 16001 filas.

3. Conteo de calidad:
   - SELECT quality_note, COUNT(*) FROM fact_viaticos WHERE quality_note IS NOT NULL GROUP BY quality_note;
