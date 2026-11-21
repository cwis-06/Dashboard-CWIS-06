# Folder sql/

File di folder ini **tidak** dijalankan otomatis, kecuali `skema_db_aktual.sql` yang *ditulis* otomatis.

| File | Isi |
|---|---|
| `skema_db_aktual.sql` | **Sumber kebenaran.** Ditulis ulang oleh `update_dashboard.bat` setiap jalan (`pg_dump` schema `sewer` dan `staging` tanpa data, ditambah isi `ref_stage` dan `ref_work_stage`). Bila database perlu dibangun ulang, mulai dari file ini. Perubahan yang dibuat langsung di pgAdmin atau DB Manager QGIS ikut tercatat di sini, dan riwayatnya terlihat di git. |
| `isi_plan_date_msp.sql` | Mengisi `plan_date` pipa dan manhole dari kertas kerja MSP, membuat `urutan_zona2` (2 alternatif urutan jacking Zona 2) dan `pengaturan`. Dijalankan manual bila jadwal MSP berubah. Pilih alternatif: `SELECT sewer.terapkan_urutan_zona2(1);` atau `(2)`. |
| `test_pit.sql` | Tabel `sewer.test_pit` dan 215 titik TP 01 sampai TP 215 (sheet DOKUMEN TESTPIT & GEORADAR & BORELOG + file GPKG zona 4, 5, 6). Trigger mengisi `tp_id` dari `tp_no`, zona bila kosong, nama jalan terdekat, koordinat, dan posisi dari `mh_ref` bila titik kosong. Dijalankan `setup_otomasi.bat`; isian yang sudah ada tidak ditimpa, status hanya naik dari Direncanakan. |
| `bore_log.sql` | Tabel `sewer.bore_log` (layer Bore log / soil boring) dan 22 titik: 18 dari sheet, ditambah 4 dari laporan WhatsApp (BH 46 menggantikan BH 06 di MH 0755, BH 47, MH 0772A, MH 0775). Titik tanpa koordinat diambil dari posisi manhole. Dijalankan `setup_otomasi.bat`. |
| `sinkron_test_pit.sql` | Tabel `staging.tp_sheet` dan fungsi `sewer.sinkron_test_pit()` untuk memperbarui `test_pit` dari tab TEST PIT di Google Sheet. Dipasang `setup_otomasi.bat`, dijalankan `update_dashboard.bat` langkah [2/7]. Panduan: `panduan/01_sinkron_test_pit.md`. |
| `diagnosa.sql` | Hanya membaca: `ref_stage`, definisi view, trigger, fungsi, versi. Dipakai `cek_database.bat`. |

## `arsip/`

Hanya riwayat. **Jangan dijalankan**: database yang berlaku sudah memakai versi yang disesuaikan (misalnya `trg_lp` dan `trg_mh` yang memvalidasi tahap dengan metode `ALL`), dan file lama akan menimpanya.

- Skema dan migrasi awal: `sewerage_webgis_schema.sql`, `aset_baru_cwis06.sql`, `migrasi_manhole_pipa.sql`, `progress_manhole.sql`.
- Otomasi lama: `otomasi_qgis.sql`, `otomasi_qgis_hapus.sql`, `otomasi_qgis_posisi.sql`, `otomasi_qgis_sinkron.sql`.

Kondisi database 20 November 2026: PostgreSQL 15.2, PostGIS 3.3.2. `ref_stage` berisi 5 tahap untuk `lateral_pipe` dan `manhole`, semuanya metode `ALL` (`belum_mulai` 0, `galian_shaft` 25, `jacking` 50, `pemasangan_manhole` 75, `pekerjaan_selesai` 100).
