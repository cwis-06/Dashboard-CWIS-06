@echo off
setlocal
title Pasang otomasi database CWIS-06
rem Memasang (aman diulang):
rem   otomasi_qgis_monitor.sql : view pipa, pemeriksaan data (QA), riwayat progres
rem   sql\test_pit.sql         : tabel test pit + 150 titik (titik yang sudah ada tidak ditimpa)
rem Fungsi lain di database sudah disesuaikan langsung dan TIDAK disentuh.
rem Struktur lengkap yang berlaku ada di sql\skema_db_aktual.sql.
cd /d "%~dp0"
call _koneksi.bat || goto :akhir
echo Memasang otomasi ke %DB_NAME% di %DB_HOST% ...
for %%F in (otomasi_qgis_monitor.sql sql\test_pit.sql) do (
  echo   %%F
  "%PSQL%" -w -q -X -v ON_ERROR_STOP=1 --single-transaction -f "%%F" || (
    echo Gagal di %%F; perubahan file ini dibatalkan. Baca pesan di atas.
    goto :akhir
  )
)
echo Selesai. Cukup edit di QGIS, Save Edits, lalu jalankan update_dashboard.bat.
:akhir
echo.
pause
endlocal
