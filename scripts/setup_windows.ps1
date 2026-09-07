# Setup script for AI Image Studio on Windows.
# - Creates Python venv (.venv), upgrades pip, installs requirements.txt
# - Runs `flutter pub get` inside flutter_app/
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
# Fallback: repo layout ai_image_studio/scripts -> project root is parent of scripts dir
$ProjectRoot = Join-Path (Get-Location) "ai_image_studio"
if (Test-Path (Join-Path $Root "python_engine")) { $ProjectRoot = $Root }

Write-Host "Project root: $ProjectRoot"

$VenvDir = Join-Path $ProjectRoot ".venv"
$Requirements = Join-Path $ProjectRoot "python_engine\requirements.txt"
$FlutterApp = Join-Path $ProjectRoot "flutter_app"

# 1. Python venv
if (-not (Test-Path $VenvDir)) {
    Write-Host "Creating Python virtual environment..."
    python -m venv $VenvDir
} else {
    Write-Host "Virtual environment already exists."
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
Write-Host "Upgrading pip..."
& $VenvPython -m pip install --upgrade pip

Write-Host "Installing Python requirements..."
& $VenvPython -m pip install -r $Requirements

# 2. Flutter deps
Write-Host "Enabling Windows desktop..."
flutter config --enable-windows-desktop

Write-Host "Running flutter pub get..."
Push-Location $FlutterApp
flutter pub get
Pop-Location

Write-Host "Setup complete."
