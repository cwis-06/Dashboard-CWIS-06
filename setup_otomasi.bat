@echo off
setlocal
title Pasang otomasi database CWIS-06
rem Memasang ulang view, pemeriksaan data (QA), dan riwayat progres dari otomasi_qgis_monitor.sql.
rem Aman diulang. Fungsi lain di database sudah disesuaikan langsung dan TIDAK disentuh.
rem Struktur lengkap yang berlaku ada di sql\skema_db_aktual.sql.
cd /d "%~dp0"
call _koneksi.bat || goto :akhir
echo Memasang otomasi ke %DB_NAME% di %DB_HOST% ...
"%PSQL%" -w -q -X -v ON_ERROR_STOP=1 --single-transaction -f otomasi_qgis_monitor.sql ^
  && echo Selesai. Cukup edit di QGIS, Save Edits, lalu jalankan update_dashboard.bat. ^
  || echo Gagal; seluruh perubahan dibatalkan. Baca pesan di atas.
:akhir
echo.
pause
endlocal
