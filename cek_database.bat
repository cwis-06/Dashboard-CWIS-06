@echo off
setlocal
title Cek database CWIS-06
rem Hanya MEMBACA database (sql\diagnosa.sql) dan menulis hasil ke diagnosa_hasil.txt.
rem diagnosa_hasil.txt tidak ikut ke GitHub.
cd /d "%~dp0"
call _koneksi.bat || goto :akhir
echo Membaca database %DB_NAME% ...
"%PSQL%" -w -X -f sql\diagnosa.sql > diagnosa_hasil.txt 2>&1
echo Selesai. Hasil: %~dp0diagnosa_hasil.txt
:akhir
echo.
pause
endlocal
