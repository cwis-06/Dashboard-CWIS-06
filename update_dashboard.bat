@echo off
setlocal
title Update Dashboard Sewerage

rem ================= PENGATURAN BAWAAN =================
rem Jangan ubah di sini. Untuk pengaturan komputer Anda sendiri, salin
rem config_lokal.contoh.bat menjadi config_lokal.bat lalu ubah isinya.
rem config_lokal.bat tidak ikut terunggah ke GitHub.
set DB_HOST=localhost
set DB_PORT=5432
set DB_NAME=db_cwis06
set DB_USER=postgres
set SRC_SRID=32749
set QGIS_DIR=
set PSQL=
rem QA_WAJIB=1: temuan level ERROR menghentikan unggahan. 0: hanya peringatan.
set QA_WAJIB=1
rem =====================================================
rem Skrip menyalin dirinya ke folder TEMP lalu berjalan dari sana, supaya aman
rem ketika git mengubah file di folder repo (termasuk file ini sendiri).
rem Sebelum menjalankan: di QGIS klik Save Edits agar perubahan masuk ke database.

if /i not "%~dp0"=="%TEMP%\" (
  copy /y "%~f0" "%TEMP%\update_dashboard_run.bat" >nul
  call "%TEMP%\update_dashboard_run.bat" "%~dp0"
  exit /b
)
set "REPO=%~1"
cd /d "%REPO%"
if exist "config_lokal.bat" call "config_lokal.bat"

rem ---------- Kunci: cegah dua jendela berjalan bersamaan di komputer ini ----------
set "LOCK=%TEMP%\update_dashboard_cwis06.lock"
if exist "%LOCK%" (
  powershell -NoProfile -Command "if(((Get-Date)-(Get-Item $env:LOCK).LastWriteTime).TotalMinutes -gt 30){exit 0}else{exit 1}"
  if errorlevel 1 (
    echo update_dashboard.bat sedang berjalan di jendela lain di komputer ini.
    echo Jika yakin tidak ada yang berjalan, hapus file berikut lalu ulangi:
    echo   %LOCK%
    goto :gagal_tanpa_kunci
  )
  del "%LOCK%" >nul 2>&1
)
echo %DATE% %TIME% > "%LOCK%"

if not exist ".git" (
  echo Folder ini bukan repo Git. Jalankan git clone dulu, lalu salin file ini ke folder hasil clone.
  goto :gagal
)
where git >nul 2>&1
if errorlevel 1 (
  echo Git belum terpasang. Pasang Git for Windows dari git-scm.com.
  goto :gagal
)
git config core.autocrlf false

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm'"`) do set "STAMP=%%T"
set "OPERATOR="
for /f "usebackq delims=" %%U in (`git config user.name`) do set "OPERATOR=%%U"
if not defined OPERATOR set "OPERATOR=%USERNAME%"

rem o4w_env.bat milik QGIS mengganti PATH (git dan powershell jadi tidak ditemukan), jadi PATH asli disimpan dulu.
set "ORIGPATH=%PATH%"

rem Koneksi database lewat variabel lingkungan; dipakai psql dan ogr2ogr.
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

echo [1/6] Sinkron dengan GitHub ...
git pull --rebase --autostash
if errorlevel 1 goto :gagal
git ls-files -u | findstr . >nul
if not errorlevel 1 (
  echo Ada file yang konflik setelah sinkron. Proses dihentikan agar tidak mengunggah file rusak.
  git status --short
  goto :gagal
)

if not defined PSQL for /d %%D in ("C:\Program Files\PostgreSQL\*") do if exist "%%~fD\bin\psql.exe" set "PSQL=%%~fD\bin\psql.exe"
if not defined PSQL (
  echo psql tidak ditemukan di C:\Program Files\PostgreSQL.
  echo Pasang PostgreSQL Command Line Tools, atau isi PSQL di config_lokal.bat.
  goto :gagal
)

echo [2/6] Menghitung ulang kolom otomatis ...
"%PSQL%" -w -q -X -v ON_ERROR_STOP=1 -c "CALL sewer.refresh_all();"
if errorlevel 1 (
  echo Penghitungan ulang gagal, data TIDAK diunggah.
  echo Bila pesannya menyebut refresh_all tidak ada, jalankan setup_otomasi.bat dulu.
  goto :gagal
)

echo [3/6] Memeriksa kualitas data ...
"%PSQL%" -w -q -X -v ON_ERROR_STOP=1 -A -t -F " | " -c "SELECT level, check_name, n, coalesce(contoh, '') FROM sewer.qa_report() WHERE n > 0 ORDER BY CASE level WHEN 'ERROR' THEN 0 WHEN 'PERINGATAN' THEN 1 ELSE 2 END, check_name"
if errorlevel 1 (
  echo Pemeriksaan data tidak bisa dijalankan. Jalankan setup_otomasi.bat dulu.
  goto :gagal
)
set "QAERR=0"
for /f "usebackq delims=" %%N in (`call "%PSQL%" -w -q -X -A -t -c "SELECT count(*) FROM sewer.qa_report() WHERE level = 'ERROR' AND n > 0"`) do set "QAERR=%%N"
if not "%QAERR%"=="0" (
  if "%QA_WAJIB%"=="1" (
    echo.
    echo Ada %QAERR% jenis temuan ERROR di atas. Perbaiki di QGIS, Save Edits, lalu jalankan lagi.
    echo Data TIDAK diunggah.
    goto :gagal
  )
  echo Peringatan: ada temuan ERROR, tetapi QA_WAJIB=0 sehingga unggahan tetap dilanjutkan.
)

echo [4/6] Menyimpan riwayat progres dan struktur database ...
"%PSQL%" -w -q -X -v ON_ERROR_STOP=1 -c "CALL sewer.snapshot_progress();"
if errorlevel 1 echo Peringatan: riwayat progres gagal disimpan. Unggahan tetap dilanjutkan.
call :simpan_skema

set /a COBA=0
:publikasi
set /a COBA+=1
echo [5/6] Mengekspor layer ke data\ ...
call :ekspor_semua
if errorlevel 1 goto :gagal

findstr /m /c:"<<<<<<<" index.html README.md js\app.js >nul 2>&1
if not errorlevel 1 (
  echo index.html, README.md, atau js\app.js masih mengandung tanda konflik git. Proses dihentikan.
  goto :gagal
)

echo [6/6] Mengunggah ke GitHub ...
rem Ikut terunggah: data, halaman, skrip, SQL, dan foto\Code.gs. Tile ortofoto tetap manual.
for %%P in (data index.html README.md js css img foto sql .gitignore "*.sql" "*.bat") do git add -A -- %%P >nul 2>&1
git diff --cached --quiet -- data
if errorlevel 1 (
  powershell -NoProfile -Command "$m=[ordered]@{updated=(Get-Date -Format o); operator=$env:OPERATOR}; [IO.File]::WriteAllText((Join-Path (Get-Location) 'data\meta.json'), ($m | ConvertTo-Json -Compress))"
  git add -- data/meta.json
)
git diff --cached --quiet
if errorlevel 1 (
  git commit -q -m "Update data %STAMP% oleh %OPERATOR%"
  if errorlevel 1 goto :gagal
) else (
  echo Tidak ada perubahan baru.
)
git push -q
if not errorlevel 1 goto :berhasil

if %COBA% geq 3 (
  echo Push masih ditolak setelah 3 kali percobaan.
  goto :gagal
)
echo Push ditolak karena ada pembaruan dari komputer lain. Menyesuaikan lalu mengekspor ulang ...
git pull --rebase --autostash -X theirs
if errorlevel 1 (
  git rebase --abort >nul 2>&1
  echo Sinkron ulang gagal. Hubungi pengelola repo.
  goto :gagal
)
rem Ekspor ulang dari database supaya file data utuh, bukan hasil gabungan baris.
goto :publikasi

:berhasil
echo.
echo Selesai. Dashboard akan terbarui dalam 1-2 menit. Muat ulang halaman dengan Ctrl+F5.
goto :selesai

rem ================= SUBRUTIN =================
:simpan_skema
rem Struktur database yang BERLAKU (tabel, view, fungsi, trigger) + isi ref_stage disimpan ke
rem sql\skema_db_aktual.sql, supaya perubahan yang dibuat langsung di database tetap tercatat di repo.
set "PGDUMP="
for %%I in ("%PSQL%") do set "PGDUMP=%%~dpIpg_dump.exe"
if not exist "%PGDUMP%" goto :skema_lewat
set "SKTMP=%TEMP%\cwis06_skema.sql"
"%PGDUMP%" -w -s -n sewer -n staging -T "sewer.bak_*" --no-owner --no-privileges -f "%SKTMP%"
if errorlevel 1 goto :skema_gagal
"%PGDUMP%" -w -a --inserts -t sewer.ref_stage -t sewer.ref_work_stage >> "%SKTMP%"
if errorlevel 1 goto :skema_gagal
if not exist sql mkdir sql
powershell -NoProfile -Command "Get-Content -Encoding UTF8 $env:SKTMP | Where-Object { $_ -notmatch '^\\(un)?restrict ' } | Set-Content -Encoding UTF8 'sql\skema_db_aktual.sql'"
if errorlevel 1 goto :skema_gagal
echo   struktur database tersimpan di sql\skema_db_aktual.sql
exit /b 0
:skema_lewat
echo   Dilewati: pg_dump tidak ditemukan di folder psql.
exit /b 0
:skema_gagal
echo   Peringatan: struktur database gagal disimpan. Unggahan tetap dilanjutkan.
exit /b 0

:ekspor_semua
if not defined QGIS_DIR for /d %%D in ("C:\Program Files\QGIS*") do set "QGIS_DIR=%%~fD"
if not defined QGIS_DIR (
  echo Folder QGIS tidak ditemukan di C:\Program Files. Isi QGIS_DIR di config_lokal.bat.
  exit /b 1
)
call "%QGIS_DIR%\bin\o4w_env.bat" >nul 2>&1
where ogr2ogr >nul 2>&1
if errorlevel 1 (
  echo ogr2ogr tidak ditemukan di instalasi QGIS: %QGIS_DIR%
  set "PATH=%ORIGPATH%"
  exit /b 1
)
if not exist data mkdir data
rem Format: call :ekspor NAMA_TABEL NAMA_FILE WAJIB(1/0). Layer opsional dilewati bila tabelnya belum ada.
call :ekspor v_lateral_pipe v_lateral_pipe 1
if errorlevel 1 goto :ekspor_gagal
call :ekspor v_manhole v_manhole 1
if errorlevel 1 goto :ekspor_gagal
call :ekspor house_inlet house_inlet 0
call :ekspor inspection_chamber inspection_chamber 0
call :ekspor collecting_pipe collecting_pipe 0
call :ekspor persil_pipe persil_pipe 0
call :ekspor zone_area zona 0
call :ekspor rw_boundary batas_rw 0
call :ekspor_riwayat
set "PATH=%ORIGPATH%"
exit /b 0
:ekspor_gagal
set "PATH=%ORIGPATH%"
exit /b 1

:ekspor
set "OUTF=data\%2.geojson"
set "TMPF=data\%2.tmp.geojson"
if exist "%TMPF%" del "%TMPF%"
echo   %1
ogr2ogr -f GeoJSON -s_srs EPSG:%SRC_SRID% -t_srs EPSG:4326 -lco COORDINATE_PRECISION=7 "%TMPF%" "PG:host=%DB_HOST% port=%DB_PORT% dbname=%DB_NAME% user=%DB_USER%" -sql "SELECT * FROM sewer.%1"
if errorlevel 1 goto :gagal_ekspor
if not exist "%TMPF%" goto :gagal_ekspor
move /y "%TMPF%" "%OUTF%" >nul
exit /b 0
:gagal_ekspor
if exist "%TMPF%" del "%TMPF%"
if "%3"=="1" exit /b 1
echo   Dilewati: %1 belum ada di database atau gagal diekspor.
exit /b 0

:ekspor_riwayat
set "TMPF=data\progress_history.tmp.csv"
if exist "%TMPF%" del "%TMPF%"
echo   progress_snapshot
ogr2ogr -f CSV "%TMPF%" "PG:host=%DB_HOST% port=%DB_PORT% dbname=%DB_NAME% user=%DB_USER%" -sql "SELECT snap_date, zone, pipe_n, pipe_len_m, pipe_done_m, pipe_pct, pipe_selesai, mh_n, mh_selesai, mh_pct FROM sewer.progress_snapshot ORDER BY snap_date, zone"
if errorlevel 1 goto :gagal_riwayat
if not exist "%TMPF%" goto :gagal_riwayat
move /y "%TMPF%" "data\progress_history.csv" >nul
exit /b 0
:gagal_riwayat
if exist "%TMPF%" del "%TMPF%"
echo   Dilewati: riwayat progres belum ada. Jalankan setup_otomasi.bat.
exit /b 0

:gagal
echo.
echo Proses dihentikan karena ada kesalahan. Baca pesan di atas.

:selesai
if exist "%LOCK%" del "%LOCK%" >nul 2>&1
echo.
pause
endlocal
exit /b

:gagal_tanpa_kunci
echo.
pause
endlocal
