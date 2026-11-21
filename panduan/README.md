# Panduan langkah demi langkah WebGIS CWIS-06

Folder ini berisi panduan per fitur, ditulis berurutan supaya orang lain bisa
memasang ulang (replikasi) tanpa harus bertanya. Setiap panduan memuat:
tujuan, cara kerja, file yang terlibat, langkah pemasangan sekali, pemakaian
harian, dan pemecahan masalah.

## Gambaran alur data

```
                      Google Sheet "TEST PIT" ──(01)──┐
                                                       v
QGIS ──Save Edits──> PostgreSQL/PostGIS (db_cwis06) ──> update_dashboard.bat ──> GitHub ──> WebGIS (GitHub Pages)
                                                                                              │
HP petugas ──(03 watermark)──> Apps Script ──> Google Drive + Sheet foto ──(02)──> SharePoint Waskita
```

## Urutan pemasangan dari nol

| Urutan | Yang dikerjakan | Dokumen |
|---|---|---|
| 1 | Pasang PostgreSQL + PostGIS, QGIS, dan Git; clone repo | `README.md` (root) bagian B1, langkah 1 |
| 2 | Hubungkan ke database (`config_lokal.bat`, password) | `README.md` bagian B1, langkah 2 dan 3 |
| 3 | Pasang otomasi database: jalankan `setup_otomasi.bat` | `README.md` bagian B1, langkah 4 |
| 4 | Pasang foto dokumentasi (Apps Script + Drive + Sheet) | `README.md` bagian B8 |
| 5 | Sinkron test pit dari Google Sheet | [01_sinkron_test_pit.md](01_sinkron_test_pit.md) |
| 6 | Salinan foto otomatis ke SharePoint Waskita | [02_foto_ke_sharepoint.md](02_foto_ke_sharepoint.md) |
| 7 | Watermark foto kamera (sudah aktif di `js/app.js`) | [03_watermark_foto_kamera.md](03_watermark_foto_kamera.md) |

## Pekerjaan harian setelah semua terpasang

1. Edit data di QGIS lalu **Save Edits**, atau isi tab TEST PIT di Google Sheet.
2. Jalankan `update_dashboard.bat`.
3. Buka dashboard setelah 1-2 menit, tekan Ctrl+F5.

Foto lapangan dan salinannya ke SharePoint berjalan sendiri, tidak perlu
menjalankan apa pun.

## Hal rahasia yang TIDAK boleh masuk repo

Repo ini publik. Simpan hal berikut hanya di komputer atau di layanan masing-masing:

- ID Google Sheet dan folder Drive (`TP_SHEET_ID`, `FOLDER_ID`, `SHEET_ID`)
- kode akses unggah foto (`KODE_AKSES`)
- password database (pakai `pgpass.conf` atau isi saat ditanya)
- `config_lokal.bat` (sudah diabaikan oleh `.gitignore`)
