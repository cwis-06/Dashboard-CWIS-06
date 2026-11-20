@echo off
rem =====================================================================
rem Pengaturan koneksi bersama. Dipanggil oleh update_dashboard.bat,
rem setup_otomasi.bat, dan cek_database.bat; tidak dijalankan sendiri.
rem Pengaturan komputer Anda: salin config_lokal.contoh.bat menjadi
rem config_lokal.bat (tidak ikut ke GitHub).
rem =====================================================================
set "DB_HOST=localhost"
set "DB_PORT=5432"
set "DB_NAME=db_cwis06"
set "DB_USER=postgres"
set "SRC_SRID=32749"
set "QA_WAJIB=1"
set "QGIS_DIR="
set "PSQL="
if exist "%~dp0config_lokal.bat" call "%~dp0config_lokal.bat"

if not defined PSQL for /d %%D in ("C:\Program Files\PostgreSQL\*") do if exist "%%~fD\bin\psql.exe" set "PSQL=%%~fD\bin\psql.exe"
if not defined PSQL (
  echo psql tidak ditemukan di C:\Program Files\PostgreSQL. Isi PSQL di config_lokal.bat.
  exit /b 1
)
for %%I in ("%PSQL%") do set "PGDUMP=%%~dpIpg_dump.exe"

set "PGHOST=%DB_HOST%"
set "PGPORT=%DB_PORT%"
set "PGDATABASE=%DB_NAME%"
set "PGUSER=%DB_USER%"
set "PGCLIENTENCODING=UTF8"
set "PGCONN=PG:host=%DB_HOST% port=%DB_PORT% dbname=%DB_NAME% user=%DB_USER%"

rem Password dari pgpass.conf bila ada; kalau tidak, ditanya tersembunyi dan tidak disimpan.
if exist "%APPDATA%\postgresql\pgpass.conf" exit /b 0
if defined PGPASSWORD exit /b 0
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "$s=Read-Host 'Password PostgreSQL (%DB_USER%)' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))"`) do set "PGPASSWORD=%%P"
exit /b 0
