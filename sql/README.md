# Folder sql/

File di folder ini **tidak** dijalankan otomatis, kecuali `skema_db_aktual.sql` yang *ditulis* otomatis.

| File | Isi |
|---|---|
| `skema_db_aktual.sql` | **Sumber kebenaran.** Ditulis ulang oleh `update_dashboard.bat` setiap jalan (`pg_dump` schema `sewer` dan `staging` tanpa data, ditambah isi `ref_stage` dan `ref_work_stage`). Bila database perlu dibangun ulang, mulai dari file ini. Perubahan yang dibuat langsung di pgAdmin atau DB Manager QGIS ikut tercatat di sini, dan riwayatnya terlihat di git. |
| `isi_plan_date_msp.sql` | Mengisi `plan_date` pipa dan manhole dari kertas kerja MSP, membuat `urutan_zona2` (2 alternatif urutan jacking Zona 2) dan `pengaturan`. Dijalankan manual bila jadwal MSP berubah. Pilih alternatif: `SELECT sewer.terapkan_urutan_zona2(1);` atau `(2)`. |
| `test_pit.sql` | Tabel `sewer.test_pit` (trigger mengisi `tp_id`, zona bila kosong, nama jalan terdekat, koordinat) dan 150 titik TP 66 sampai TP 215. Dijalankan `setup_otomasi.bat`; titik yang sudah ada tidak ditimpa. |
| `diagnosa.sql` | Hanya membaca: `ref_stage`, definisi view, trigger, fungsi, versi. Dipakai `cek_database.bat`. |

## `arsip/`

Hanya riwayat. **Jangan dijalankan**: database yang berlaku sudah memakai versi yang disesuaikan (misalnya `trg_lp` dan `trg_mh` yang memvalidasi tahap dengan metode `ALL`), dan file lama akan menimpanya.

- Skema dan migrasi awal: `sewerage_webgis_schema.sql`, `aset_baru_cwis06.sql`, `migrasi_manhole_pipa.sql`, `progress_manhole.sql`.
- Otomasi lama: `otomasi_qgis.sql`, `otomasi_qgis_hapus.sql`, `otomasi_qgis_posisi.sql`, `otomasi_qgis_sinkron.sql`.

Kondisi database 20 November 2026: PostgreSQL 15.2, PostGIS 3.3.2. `ref_stage` berisi 5 tahap untuk `lateral_pipe` dan `manhole`, semuanya metode `ALL` (`belum_mulai` 0, `galian_shaft` 25, `jacking` 50, `pemasangan_manhole` 75, `pekerjaan_selesai` 100).
