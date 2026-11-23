@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo [Neon Grid Defense] Updating repository...
if exist ".git" (
    git pull --ff-only
)

set "GODOT_CMD=godot"
where %GODOT_CMD% >nul 2>&1
if errorlevel 1 (
    if defined GODOT_EXE (
        set "GODOT_CMD=%GODOT_EXE%"
    ) else (
        echo [ERROR] Godot 4 not found in PATH.
        echo Add Godot 4 to PATH or set GODOT_EXE to the full path of Godot_v4.3.exe
        pause
        exit /b 1
    )
)

if not exist "builds\windows" mkdir "builds\windows"

echo [Neon Grid Defense] Exporting Windows Desktop build...
"%GODOT_CMD%" --headless --path "%~dp0" --export-release "Windows Desktop" "builds\windows\NeonGridDefense.exe"
if errorlevel 1 (
    echo [ERROR] Export failed. Make sure Godot 4.3 Export Templates are installed.
    pause
    exit /b 1
)

echo [Neon Grid Defense] Build ready: builds\windows\NeonGridDefense.exe
start "" "builds\windows\NeonGridDefense.exe"
endlocal
