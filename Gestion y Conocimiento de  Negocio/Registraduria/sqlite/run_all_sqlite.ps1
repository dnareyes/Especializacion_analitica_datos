param(
    [string]$CsvPath = "./Viaticos_Registraduria_2022_2025.csv",
    [string]$DbPath = "./sqlite/viaticos_dw.sqlite",
    [string]$CsvOutDir = "./sqlite/exports",
    [switch]$Overwrite,
    [switch]$ExportCsv
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$venvPython = Join-Path $projectRoot ".venv/Scripts/python.exe"
$pythonCmd = if (Test-Path $venvPython) { $venvPython } else { "python" }

$buildScript = Join-Path $PSScriptRoot "generate_sqlite_dw.py"
$exportScript = Join-Path $PSScriptRoot "export_sqlite_tables_to_csv.py"

$buildArgs = @($buildScript, "--csv", $CsvPath, "--db", $DbPath)
if ($Overwrite) {
    $buildArgs += "--overwrite"
}

Write-Host "Construyendo archivo SQLite..."
& $pythonCmd @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "Fallo la construccion de SQLite."
}

if ($ExportCsv) {
    Write-Host "Exportando tablas a CSV..."
    & $pythonCmd $exportScript --db $DbPath --outdir $CsvOutDir
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo la exportacion de CSV."
    }
}

Write-Host "Proceso finalizado." -ForegroundColor Green
