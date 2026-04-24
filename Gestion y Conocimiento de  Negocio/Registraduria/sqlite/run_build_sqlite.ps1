param(
    [string]$CsvPath = "./Viaticos_Registraduria_2022_2025.csv",
    [string]$DbPath = "./sqlite/viaticos_dw.sqlite",
    [switch]$Overwrite
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$venvPython = Join-Path $projectRoot ".venv/Scripts/python.exe"
$pythonCmd = if (Test-Path $venvPython) { $venvPython } else { "python" }

$buildScript = Join-Path $PSScriptRoot "generate_sqlite_dw.py"
$args = @($buildScript, "--csv", $CsvPath, "--db", $DbPath)
if ($Overwrite) {
    $args += "--overwrite"
}

& $pythonCmd @args
if ($LASTEXITCODE -ne 0) {
    throw "Fallo la construccion de SQLite."
}
