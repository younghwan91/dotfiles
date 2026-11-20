@echo off
rem update              = uv tools + global npm, then (elevated, one UAC prompt) winget + Windows Update + WSL kernel
rem update --check      = only list what winget would upgrade
rem update <args>       = passed straight to winget, e.g. "update install foo"
rem Same shape as `update` in zsh/os/linux.zsh (apt). Each step prints a "==> [n/5]" header.
if "%~1"=="--check" ( winget upgrade & exit /b )
if not "%~1"=="" if not "%~1"=="--elevated" ( winget %* & exit /b )
if "%~1"=="--elevated" goto elevated

echo.
echo ==^> [1/5] uv tools upgrade
where uv >nul 2>&1 || echo     uv not found, skipped
where uv >nul 2>&1 && uv tool upgrade --all
echo.
echo ==^> [2/5] npm global update
where npm >nul 2>&1 || echo     npm not found, skipped
where npm >nul 2>&1 && call npm update -g

rem winget packages and Windows Update need admin: relaunch once so there is a single prompt.
fltmc >nul 2>&1 && goto elevated
echo.
echo ==^> Steps 3-5 need admin: continuing in an elevated window...
powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0' -ArgumentList '--elevated'"
exit /b

:elevated
echo.
echo ==^> [3/5] winget upgrade
winget source update
winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements
echo.
echo ---- still outdated after upgrade ----
winget upgrade
echo.
echo ==^> [4/5] Windows Update
pwsh -NoProfile -File "%~dp0update-windows.ps1" -NoPause
echo.
echo ==^> [5/5] WSL update
where wsl >nul 2>&1 || echo     wsl not found, skipped
where wsl >nul 2>&1 && wsl --update
echo.
echo ==^> update done
if "%~1"=="--elevated" pause
