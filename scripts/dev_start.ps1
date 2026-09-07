# Dev launcher: FastAPI server in one background terminal + Flutter Windows app.
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Fallback = Join-Path (Get-Location) "ai_image_studio"
if (-not (Test-Path (Join-Path $ProjectRoot "python_engine"))) { $ProjectRoot = $Fallback }

$VenvPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$EngineApp = Join-Path $ProjectRoot "python_engine\app.py"
$FlutterApp = Join-Path $ProjectRoot "flutter_app"

if (-not (Test-Path $VenvPython)) { $VenvPython = "python" }

Write-Host "Starting FastAPI engine in a new terminal..."
Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '$VenvPython' '$EngineApp'"

Write-Host "Starting Flutter app on Windows..."
Push-Location $FlutterApp
flutter run -d windows
Pop-Location
