# Folder sql/

File di folder ini **tidak** dijalankan oleh `setup_otomasi.bat`.

## Sumber kebenaran: `skema_db_aktual.sql`

Ditulis ulang otomatis oleh `update_dashboard.bat` setiap kali dijalankan (`pg_dump` schema `sewer` dan `staging` tanpa data, ditambah isi `ref_stage` dan `ref_work_stage`). Inilah struktur database yang **sedang berlaku**: tabel, view, fungsi, dan trigger. Bila database perlu dibangun ulang, mulai dari file ini. Perubahan yang dibuat langsung di pgAdmin atau DB Manager QGIS akan ikut tercatat di sini pada update berikutnya, dan riwayatnya bisa dilihat lewat git.

## File lain

| File | Isi |
|---|---|
| `diagnosa.sql` | Membaca isi `ref_stage`, definisi view, trigger, dan fungsi. Dipakai `cek_database.bat`. Tidak mengubah apa pun. |
| `sewerage_webgis_schema.sql` | Skema awal (riwayat). |
| `aset_baru_cwis06.sql` | Tabel aset tambahan: house inlet, IC, collecting, persil, zona, RW (riwayat). |
| `migrasi_manhole_pipa.sql` | Migrasi awal dari `staging.*_raw` ke `sewer` (riwayat). |
| `progress_manhole.sql` | Tabel `manhole_work` dan view `v_manhole` versi awal (riwayat). |

## `arsip/`

`otomasi_qgis.sql`, `otomasi_qgis_hapus.sql`, `otomasi_qgis_posisi.sql`, dan `otomasi_qgis_sinkron.sql` versi lama dari folder Downloads. **Jangan dijalankan.** Database yang berlaku sudah memakai versi yang disesuaikan, misalnya `trg_lp` dan `trg_mh` yang memvalidasi tahap dengan metode `ALL`. Menjalankan file arsip akan menimpa versi tersebut.

Hasil diagnosa 20 Nov 2026: `ref_stage` berisi 5 tahap untuk `lateral_pipe` dan `manhole`, semuanya metode `ALL` (`belum_mulai` 0, `galian_shaft` 25, `jacking` 50, `pemasangan_manhole` 75, `pekerjaan_selesai` 100). PostgreSQL 15.2, PostGIS 3.3.2.
