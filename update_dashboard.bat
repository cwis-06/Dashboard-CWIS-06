@echo off
setlocal
title Update Dashboard CWIS-06
rem Sebelum menjalankan: di QGIS klik Save Edits.
rem Skrip berjalan dari salinan di TEMP supaya aman ketika git memperbarui file ini.
if /i not "%~dp0"=="%TEMP%\" (
  copy /y "%~f0" "%TEMP%\update_dashboard_run.bat" >nul
  call "%TEMP%\update_dashboard_run.bat" "%~dp0"
  exit /b
)
cd /d "%~1"
call _koneksi.bat || goto :gagal_tanpa_kunci

rem ---- Cegah dua jendela berjalan bersamaan (kunci kedaluwarsa setelah 30 menit) ----
set "LOCK=%TEMP%\update_dashboard_cwis06.lock"
if exist "%LOCK%" powershell -NoProfile -Command "exit [int](((Get-Date)-(Get-Item $env:LOCK).LastWriteTime).TotalMinutes -lt 30)"
if errorlevel 1 (
  echo Update sedang berjalan di jendela lain. Bila yakin tidak, hapus %LOCK%
  goto :gagal_tanpa_kunci
)
echo %DATE% %TIME%> "%LOCK%"

if not exist ".git" ( echo Folder ini bukan repo Git hasil clone. & goto :gagal )
where git >nul 2>&1 || ( echo Git belum terpasang ^(git-scm.com^). & goto :gagal )
git config core.autocrlf false
for /f "delims=" %%U in ('git config user.name') do set "OPERATOR=%%U"
if not defined OPERATOR set "OPERATOR=%USERNAME%"
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm'"') do set "STAMP=%%T"
set "ORIGPATH=%PATH%"
set "SQL="%PSQL%" -w -q -X -v ON_ERROR_STOP=1"

echo [1/6] Sinkron dengan GitHub ...
git pull --rebase --autostash || goto :gagal
git ls-files -u | findstr . >nul && ( echo Ada file konflik setelah sinkron. & git status --short & goto :gagal )

echo [2/6] Menghitung ulang kolom otomatis ...
%SQL% -c "CALL sewer.refresh_all();" || ( echo Gagal. Bila fungsi tidak ada, jalankan setup_otomasi.bat. & goto :gagal )

echo [3/6] Memeriksa kualitas data ...
%SQL% -A -t -F " | " -c "SELECT level, check_name, n, coalesce(contoh,'') FROM sewer.qa_report() WHERE n > 0 ORDER BY CASE level WHEN 'ERROR' THEN 0 WHEN 'PERINGATAN' THEN 1 ELSE 2 END, check_name" || goto :gagal
rem Tanpa "-v ON_ERROR_STOP=1": tanda = di dalam for /f dibaca cmd sebagai pemisah dan merusak perintah.
set "QAERR="
for /f "usebackq" %%N in (`call "%PSQL%" -w -q -X -A -t -c "SELECT count(*) FROM sewer.qa_report() WHERE level='ERROR' AND n>0"`) do set "QAERR=%%N"
if not defined QAERR ( echo Jumlah temuan ERROR tidak bisa dibaca. Data TIDAK diunggah. & goto :gagal )
if not "%QAERR%"=="0" if "%QA_WAJIB%"=="1" (
  echo Ada %QAERR% jenis temuan ERROR. Perbaiki di QGIS, Save Edits, lalu ulangi. Data TIDAK diunggah.
  goto :gagal
)

echo [4/6] Menyimpan riwayat progres dan struktur database ...
%SQL% -c "CALL sewer.snapshot_progress();" || echo   Peringatan: riwayat progres gagal disimpan.
call :simpan_skema

set /a COBA=0
:publikasi
set /a COBA+=1
echo [5/6] Mengekspor layer ke data\ ...
call :ekspor_semua || goto :gagal

echo [6/6] Mengunggah ke GitHub ...
findstr /m /c:"<<<<<<<" index.html README.md js\app.js >nul 2>&1 && ( echo Masih ada tanda konflik git. & goto :gagal )
for %%P in (data index.html README.md js css img foto sql .gitignore "*.sql" "*.bat") do git add -A -- %%P >nul 2>&1
git diff --cached --quiet -- data || (
  powershell -NoProfile -Command "[IO.File]::WriteAllText('data\meta.json', (@{updated=(Get-Date -Format o); operator=$env:OPERATOR} | ConvertTo-Json -Compress))"
  git add -- data/meta.json
)
git diff --cached --quiet && echo   Tidak ada perubahan baru.
git diff --cached --quiet || git commit -q -m "Update data %STAMP% oleh %OPERATOR%" || goto :gagal
git push -q && goto :berhasil
if %COBA% geq 3 ( echo Push ditolak 3 kali. & goto :gagal )
echo Ada pembaruan dari komputer lain. Menyesuaikan lalu mengekspor ulang ...
git pull --rebase --autostash -X theirs || ( git rebase --abort >nul 2>&1 & goto :gagal )
goto :publikasi

:berhasil
echo.
echo Selesai. Dashboard terbarui dalam 1-2 menit (muat ulang dengan Ctrl+F5).
goto :selesai

rem ============================ SUBRUTIN ============================
:simpan_skema
rem Struktur database yang berlaku + isi ref_stage disimpan ke sql\skema_db_aktual.sql.
if not exist "%PGDUMP%" ( echo   Dilewati: pg_dump tidak ditemukan. & exit /b 0 )
set "SKTMP=%TEMP%\cwis06_skema.sql"
"%PGDUMP%" -w -s -n sewer -n staging -T "sewer.bak_*" --no-owner --no-privileges -f "%SKTMP%" ^
  && "%PGDUMP%" -w -a --inserts -t sewer.ref_stage -t sewer.ref_work_stage >> "%SKTMP%" ^
  && powershell -NoProfile -Command "Get-Content -Encoding UTF8 $env:SKTMP | Where-Object { $_ -notmatch '^\\(un)?restrict ' } | Set-Content -Encoding UTF8 'sql\skema_db_aktual.sql'" ^
  && ( echo   tersimpan: sql\skema_db_aktual.sql & exit /b 0 )
echo   Peringatan: struktur database gagal disimpan.
exit /b 0

:ekspor_semua
if not defined QGIS_DIR for /d %%D in ("C:\Program Files\QGIS*") do set "QGIS_DIR=%%~fD"
if not exist "%QGIS_DIR%\bin\o4w_env.bat" ( echo QGIS tidak ditemukan. Isi QGIS_DIR di config_lokal.bat. & exit /b 1 )
call "%QGIS_DIR%\bin\o4w_env.bat" >nul 2>&1
if not exist data mkdir data
set "RC=0"
rem Format  tabel:nama_file:wajib   (wajib=1 menghentikan proses bila gagal)
for %%L in (v_lateral_pipe:v_lateral_pipe:1 v_manhole:v_manhole:1 house_inlet:house_inlet:0 inspection_chamber:inspection_chamber:0 collecting_pipe:collecting_pipe:0 persil_pipe:persil_pipe:0 zone_area:zona:0 rw_boundary:batas_rw:0 test_pit:test_pit:0 bore_log:bore_log:0) do (
  for /f "tokens=1-3 delims=:" %%a in ("%%L") do call :ekspor %%a %%b %%c || set "RC=1"
)
echo   progress_snapshot
ogr2ogr -f CSV data\progress_history.tmp.csv "%PGCONN%" -sql "SELECT snap_date, zone, pipe_n, pipe_len_m, pipe_done_m, pipe_pct, pipe_selesai, mh_n, mh_selesai, mh_pct FROM sewer.progress_snapshot ORDER BY snap_date, zone" ^
  && move /y data\progress_history.tmp.csv data\progress_history.csv >nul
if exist data\progress_history.tmp.csv del data\progress_history.tmp.csv
set "PATH=%ORIGPATH%"
exit /b %RC%

:ekspor
echo   %1
set "TMPF=data\%2.tmp.geojson"
if exist "%TMPF%" del "%TMPF%"
ogr2ogr -f GeoJSON -s_srs EPSG:%SRC_SRID% -t_srs EPSG:4326 -lco COORDINATE_PRECISION=7 "%TMPF%" "%PGCONN%" -sql "SELECT * FROM sewer.%1" && if exist "%TMPF%" (
  move /y "%TMPF%" "data\%2.geojson" >nul
  exit /b 0
)
if exist "%TMPF%" del "%TMPF%"
if "%3"=="1" ( echo   GAGAL: %1 wajib ada. & exit /b 1 )
echo   Dilewati: %1 belum ada di database.
exit /b 0

:gagal
echo.
echo Proses dihentikan. Baca pesan di atas.
:selesai
if exist "%LOCK%" del "%LOCK%" >nul 2>&1
:gagal_tanpa_kunci
echo.
pause
endlocal
