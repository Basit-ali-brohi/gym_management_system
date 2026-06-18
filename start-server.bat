@echo off
REM ============================================================
REM  Gym Management - Backend server launcher (Windows)
REM  Double-click this file on the laptop that runs the app.
REM  Requirements on this laptop:
REM    1) Node.js installed   (https://nodejs.org  - LTS)
REM    2) MySQL installed + running, with the database imported
REM    3) server\.env filled with this laptop's MySQL details
REM  Keep this window OPEN while using the app.
REM ============================================================

cd /d "%~dp0server"

echo.
echo === Checking Node.js ===
where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js is NOT installed on this laptop.
  echo Install it from https://nodejs.org  ^(LTS version^), then run this again.
  echo.
  pause
  exit /b 1
)
node -v

echo.
if not exist "node_modules" (
  echo === Installing dependencies ^(first run only^) ===
  call npm install
)

echo.
echo === Starting backend on http://127.0.0.1:8081 ===
echo Keep this window open. Press Ctrl+C to stop.
echo.
call npm start

echo.
echo The server stopped. If you see a database error above,
echo open server\.env and fix DB_PASSWORD / DB_NAME to match this
echo laptop's MySQL, then run this file again.
echo.
pause
