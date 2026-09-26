@echo off
title Attendance System Launcher

cd /d C:\www\AttendanceSystem

REM 1. Start Python Face Verification Service (Port 5000)
cd /d C:\www\AttendanceSystem\python-services\face-verification
start "Python Face Verification" cmd /k "call ..\..\.venv\Scripts\activate.bat && python app.py"
cd /d C:\www\AttendanceSystem
timeout /t 3 /nobreak >nul

REM 2. Start Laravel LAN Server (Port 8000)
start "Laravel Server" cmd /k "php artisan serve --host=0.0.0.0 --port=8000"
timeout /t 2 /nobreak >nul

REM 3. Start Ngrok Tunnel for Laravel
start "Ngrok Tunnel" cmd /k "ngrok http 8000"

echo All core services and ngrok are running!
pause