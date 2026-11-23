@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo [Neon Grid Defense] Checking for repository updates...
if exist ".git" (
    git pull --ff-only
)

set "GODOT_CMD=godot"
where %GODOT_CMD% >nul 2>&1
if errorlevel 1 (
    if defined GODOT_EXE (
        set "GODOT_CMD=%GODOT_EXE%"
    ) else if exist "builds\windows\NeonGridDefense.exe" (
        echo [Neon Grid Defense] Godot not in PATH, launching built EXE...
        start "" "builds\windows\NeonGridDefense.exe"
        exit /b 0
    ) else (
        echo [ERROR] Godot 4 not found in PATH and no built EXE found.
        echo Install Godot 4 or set GODOT_EXE environment variable to Godot_v4.3.exe
        pause
        exit /b 1
    )
)

echo [Neon Grid Defense] Launching game...
"%GODOT_CMD%" --path "%~dp0"
endlocal
