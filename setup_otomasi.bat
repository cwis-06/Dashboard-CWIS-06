@echo off
setlocal
title Pasang otomasi database

rem ================= PENGATURAN BAWAAN =================
rem Pengaturan komputer Anda sendiri ditaruh di config_lokal.bat (tidak ikut ke GitHub).
set DB_HOST=localhost
set DB_PORT=5432
set DB_NAME=db_cwis06
set DB_USER=postgres
set PSQL=
rem =====================================================
rem Dijalankan oleh pengelola database setiap kali file di daftar FILES berubah. Aman diulang.
rem PENTING: hanya file di daftar FILES yang dijalankan. Fungsi dan trigger lain di database
rem sudah disesuaikan langsung dan TIDAK boleh ditimpa file lama (lihat sql\arsip\README di sql\README.md).
rem Struktur database yang berlaku tercatat di sql\skema_db_aktual.sql (ditulis update_dashboard.bat).
set "FILES=otomasi_qgis_monitor.sql"

cd /d "%~dp0"
if exist "config_lokal.bat" call "config_lokal.bat"

if not defined PSQL for /d %%D in ("C:\Program Files\PostgreSQL\*") do if exist "%%~fD\bin\psql.exe" set "PSQL=%%~fD\bin\psql.exe"
if not defined PSQL (
  echo psql tidak ditemukan. Jalankan isi %FILES% lewat DB Manager QGIS atau pgAdmin.
  goto :gagal
)

set "PGHOST=%DB_HOST%"
set "PGPORT=%DB_PORT%"
set "PGDATABASE=%DB_NAME%"
set "PGUSER=%DB_USER%"
set "PGCLIENTENCODING=UTF8"
rem Password: dibaca dari pgpass.conf bila ada. Kalau tidak ada, ditanyakan dengan input tersembunyi dan tidak disimpan.
if not exist "%APPDATA%\postgresql\pgpass.conf" (
  if not defined PGPASSWORD (
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "$s=Read-Host 'Password PostgreSQL untuk user %DB_USER%' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))"`) do set "PGPASSWORD=%%P"
  )
)

echo Memasang otomasi ke database %DB_NAME% di %DB_HOST% ...
for %%F in (%FILES%) do (
  if not exist "%~dp0%%F" (
    echo File %%F tidak ditemukan di folder ini.
    goto :gagal
  )
  echo   %%F
  "%PSQL%" -w -q -X -v ON_ERROR_STOP=1 --single-transaction -f "%~dp0%%F"
  if errorlevel 1 goto :gagal
)

echo.
echo Selesai. Otomasi terpasang. Dari sekarang cukup edit di QGIS, Save Edits, lalu jalankan update_dashboard.bat.
goto :selesai

:gagal
echo.
echo Proses dihentikan karena ada kesalahan. Baca pesan di atas.
echo File yang gagal dibatalkan seluruhnya; file sebelumnya tetap terpasang.

:selesai
echo.
pause
endlocal
