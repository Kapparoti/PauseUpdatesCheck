@echo off
setlocal

:: ==================================================================
:: PauseUpdatesCheck - Installer
:: Registers a Scheduled Task that runs PauseUpdatesCheck.ps1 at every log-in
:: ==================================================================

:: Self-elevate if not running as administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights to pause updates in the Registry...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Ask for the reminder threshold (in days) and save it to the Registry
set "DAYS_INPUT="
set /p "DAYS_INPUT=Enter the number of days without updates before showing a reminder (press Enter for default = 30): "
if "%DAYS_INPUT%"=="" set "DAYS_INPUT=30"

echo %DAYS_INPUT%| findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Invalid number of days entered, using default of 30 days.
    set "DAYS_INPUT=30"
)

reg add "HKLM\SOFTWARE\PauseUpdatesCheck" /v ThresholdDays /t REG_DWORD /d %DAYS_INPUT% /f >nul
echo Reminder threshold set to %DAYS_INPUT% day(s).
echo.

:: Locate the main script in the same folder
set "SCRIPT_DIR=%~dp0"
set "MAIN_SCRIPT=%SCRIPT_DIR%PauseUpdatesCheck.ps1"

if not exist "%MAIN_SCRIPT%" (
    echo ERROR: PauseUpdatesCheck.ps1 was not found in:
    echo   %SCRIPT_DIR%
    echo Make sure both files are kept in the same folder.
    pause
    exit /b 1
)

:: Register the Scheduled Task
set "TASK_NAME=PauseUpdatesCheck"

echo Removing any previous version of the task, if present...
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

echo Creating scheduled task...
schtasks /create /tn "%TASK_NAME%" /tr "\"powershell.exe\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%MAIN_SCRIPT%\"" /sc onlogon /rl highest /f

if %errorlevel% neq 0 (
    echo ERROR: Failed to create the scheduled task.
    pause
    exit /b 1
)

:: Run it once now, so the effect is visible immediately
echo.
echo Running it now for the first time...
schtasks /run /tn "%TASK_NAME%"

echo.
echo Installation complete.
echo.
echo NOTE: The script will run at every log-in directly from: %MAIN_SCRIPT%,
echo so if you move or delete it, the task will stop working correctly.
echo You will be warned after %DAYS_INPUT% day(s) without updates.

echo.
pause
