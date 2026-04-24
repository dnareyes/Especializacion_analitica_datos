param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [string]$GcsCsvUri,

    [string]$Location = "US"
)

$ErrorActionPreference = "Stop"

function Invoke-BqSqlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string]$GcsUriReplacement
    )

    if (-not (Test-Path $FilePath)) {
        throw "No existe el archivo SQL: $FilePath"
    }

    $sql = Get-Content -Path $FilePath -Raw

    if ($GcsUriReplacement) {
        $sql = $sql.Replace("gs://REEMPLAZAR_BUCKET/Viaticos_Registraduria_2022_2025.csv", $GcsUriReplacement)
    }

    $sql | bq query --project_id=$ProjectId --location=$Location --use_legacy_sql=false
}

if (-not (Get-Command bq -ErrorAction SilentlyContinue)) {
    throw "No se encontro el comando bq. Instala Google Cloud CLI y ejecuta gcloud init."
}

$schemaFile = Join-Path $PSScriptRoot "01_create_schema_bigquery.sql"
$loadFile = Join-Path $PSScriptRoot "02_load_from_gcs_bigquery.sql"
$qualityFile = Join-Path $PSScriptRoot "03_quality_checks_bigquery.sql"
$analysisFile = Join-Path $PSScriptRoot "04_analysis_queries_bigquery.sql"

Write-Host "Ejecutando schema..."
Invoke-BqSqlFile -FilePath $schemaFile

Write-Host "Ejecutando carga y normalizacion..."
Invoke-BqSqlFile -FilePath $loadFile -GcsUriReplacement $GcsCsvUri

Write-Host "Ejecutando quality checks..."
Invoke-BqSqlFile -FilePath $qualityFile

Write-Host "Ejecutando consultas analiticas base..."
Invoke-BqSqlFile -FilePath $analysisFile

Write-Host "Proceso BigQuery finalizado." -ForegroundColor Green
