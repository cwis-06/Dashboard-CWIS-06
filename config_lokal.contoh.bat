@echo off
rem Salin file ini menjadi config_lokal.bat lalu hapus "rem " di baris yang dipakai.
rem config_lokal.bat tidak ikut ke GitHub. Jangan menaruh password di sini;
rem pakai %APPDATA%\postgresql\pgpass.conf atau isi saat ditanya.

rem set DB_HOST=192.168.1.10
rem set DB_PORT=5432
rem set DB_NAME=db_cwis06
rem set DB_USER=editor_cwis06
rem set QGIS_DIR=D:\QGIS 3.40
rem set PSQL=D:\PostgreSQL\15\bin\psql.exe
rem 0 = temuan ERROR hanya peringatan (darurat saja)
rem set QA_WAJIB=0
rem Sinkron test pit dari Google Sheet (panduan\01_sinkron_test_pit.md).
rem ID = bagian alamat Sheet di antara /d/ dan /edit ; GID = angka setelah gid= pada tab TEST PIT
rem set TP_SHEET_ID=isi_id_sheet_di_sini
rem set TP_SHEET_GID=0
