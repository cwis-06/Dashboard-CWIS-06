@echo off
setlocal
title Cek database CWIS-06

rem Hanya MEMBACA database (sql\diagnosa.sql) dan menulis hasilnya ke diagnosa_hasil.txt.
rem Tidak mengubah data. diagnosa_hasil.txt tidak ikut terunggah ke GitHub.

set DB_HOST=localhost
set DB_PORT=5432
set DB_NAME=db_cwis06
set DB_USER=postgres
set PSQL=

cd /d "%~dp0"
if exist "config_lokal.bat" call "config_lokal.bat"

if not defined PSQL for /d %%D in ("C:\Program Files\PostgreSQL\*") do if exist "%%~fD\bin\psql.exe" set "PSQL=%%~fD\bin\psql.exe"
if not defined PSQL (
  echo psql tidak ditemukan. Jalankan isi sql\diagnosa.sql lewat pgAdmin atau DB Manager QGIS.
  goto :akhir
)

set "PGHOST=%DB_HOST%"
set "PGPORT=%DB_PORT%"
set "PGDATABASE=%DB_NAME%"
set "PGUSER=%DB_USER%"
set "PGCLIENTENCODING=UTF8"
if not exist "%APPDATA%\postgresql\pgpass.conf" (
  if not defined PGPASSWORD (
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "$s=Read-Host 'Password PostgreSQL untuk user %DB_USER%' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))"`) do set "PGPASSWORD=%%P"
  )
)

echo Membaca struktur database %DB_NAME% ...
"%PSQL%" -w -X -f "sql\diagnosa.sql" > "diagnosa_hasil.txt" 2>&1
echo Selesai. Hasil ada di: %~dp0diagnosa_hasil.txt

:akhir
echo.
pause
endlocal
