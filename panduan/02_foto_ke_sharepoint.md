# 02. Salinan foto otomatis ke SharePoint Waskita

## Tujuan

Foto lapangan tetap diunggah lewat WebGIS ke Google Drive, karena peta
menampilkan foto dari Drive. Setiap foto juga disalin otomatis ke SharePoint
Waskita sebagai arsip resmi untuk laporan mingguan, bulanan, dan termin,
dengan susunan folder yang sama seperti di Drive.

## Cara kerja

```
HP petugas ── WebGIS (tombol Foto) ──> Apps Script Code.gs ──> Google Drive + tab "Dokumentasi Lapangan"
                                                                   │
                     (tiap 15 menit) Apps Script Antrian.gs ───────┘
                        ├─ tab "Antrian SharePoint" (catatan semua foto)
                        └─ file Drive "antrian_sharepoint.json" (foto 7 hari terakhir)
                                                                   │
                     (tiap 30 menit) Power Automate (akun Waskita)
                        1. baca antrian_sharepoint.json (1 panggilan Google Drive)
                        2. untuk tiap foto: sudah ada di SharePoint?  ya → lewati
                                                                      tidak → salin
                                                                   v
     SharePoint (site proyek) › … › Foto WebGIS CWIS-06 › bulan › pekan › tanggal
```

Flow tidak memakai konektor Google Sheets, karena konektor itu cepat terkena
pembatasan Google (error 429 "Too many requests") bila dipanggil per foto.
Tanda "sudah disalin" adalah keberadaan file di SharePoint itu sendiri.

## Yang dibutuhkan

| Kebutuhan | Keterangan |
|---|---|
| Akun Google pemilik script foto (akun KSO) | Pemilik proyek Apps Script, Drive, dan Sheet foto |
| Akun Microsoft 365 Waskita dengan Power Automate | Cukup lisensi standar. Semua konektor yang dipakai berkelas Standard. |
| Izin edit pada site SharePoint tujuan | Site proyek di tenant Waskita |
| Konektor Google Drive dan Google Sheets diizinkan di Power Automate | Kebijakan IT perusahaan bisa memblokirnya. Tanyakan bila muncul pesan "blocked by DLP policy". |

## File yang terlibat

| File | Isi |
|---|---|
| `foto/Code.gs` | Backend unggah foto yang sudah ada (tidak diubah) |
| `foto/Antrian.gs` | Mencatat foto baru ke tab "Antrian SharePoint" |
| `antrian_sharepoint.json` (di Drive, dibuat otomatis) | Daftar foto yang dibaca flow |
| Flow Power Automate "Salin Foto WebGIS ke SharePoint" | Mengecek dan menyalin foto (tidak disimpan di repo; dibuat lewat langkah 4) |

## Langkah 1. Siapkan folder di SharePoint

1. Buka site SharePoint tujuan, lalu masuk ke folder induk dokumentasi
   (contoh: `Documents › … › 02. Engineering › 09. Dokumentasi`).
2. Klik **Create or upload → Folder**, lalu beri nama `Foto WebGIS CWIS-06`.
3. Klik folder itu, lalu buka **Details** (ikon i). Catat **Path**-nya.
4. Jangan menambah kolom baru di library yang dipakai bersama tim lain. Keterangan
   foto sudah ada di nama file.

## Langkah 2. Tambah Antrian.gs di Apps Script

1. Buka **script.google.com** dengan akun KSO, lalu buka proyek script foto
   (yang berisi `Code.gs`, di proyek CWIS-06 bernama "DOKUMENTASI").
2. Di panel **File**, klik **+ → Script**, lalu beri nama `Antrian`.
3. Hapus isi bawaan, lalu tempel seluruh isi `foto/Antrian.gs` dari repo ini.
   Tekan Ctrl+S.
4. Pilih fungsi **`siapkanAntrianSP`**, lalu klik **Jalankan**. Hasilnya di Log eksekusi:
   `Masuk antrian: N foto`.
5. Buka Sheet foto. Seharusnya ada tab baru **Antrian SharePoint** berisi daftar foto.

Bila muncul jendela izin yang gagal terbuka ("Maaf, saat ini tidak dapat membuka
file", alamat berisi `authuser=1`): browser sedang login lebih dari satu akun
Google. Pakai jendela browser yang hanya login akun KSO.

## Langkah 3. Pasang pemicu 15 menit

1. Di Apps Script, klik ikon **jam (Pemicu)** di bilah kiri, lalu **+ Tambahkan Pemicu**.
2. Isi:
   - Fungsi: `isiAntrianSP`
   - Sumber acara: Berdasarkan waktu
   - Jenis: Timer menit
   - Interval: Setiap 15 menit
3. Klik **Simpan**.

Pemicu sengaja dibuat lewat menu, bukan dari kode, supaya tidak butuh izin tambahan.

## Langkah 4. Buat flow Power Automate

Buka **make.powerautomate.com** dengan akun Waskita, lalu pilih
**+ Create → Scheduled cloud flow**. Beri nama `Salin Foto WebGIS ke SharePoint`,
atur **Repeat every 30 Minute**, lalu klik **Create**.

Pada kotak bertanda **fx**, klik kotaknya, ketik `/`, pilih **Insert expression**,
lalu tempel rumusnya.

| No | Langkah (konektor → aksi) | Isian |
|---|---|---|
| 0 | **Recurrence** → Settings | **Concurrency control: On**, Degree of parallelism **1** (supaya jalan tidak tumpang tindih) |
| 1 | Google Drive → **Get file content using id** | File: pilih `antrian_sharepoint.json` lewat ikon folder. **Infer Content Type: No**. Ganti nama langkah jadi **Baca antrian** (… → Rename). Login akun Google KSO saat diminta. |
| 2 | Data Operation → **Compose** | Inputs (fx): `json(base64ToString(body('Baca_antrian')?['$content']))` |
| 3 | Control → **Apply to each** | Output: ikon petir → **Outputs** dari Compose |
| 3a | SharePoint → **Get file metadata using path** (di dalam Apply to each) | Site: site tujuan. File Path (fx): lihat rumus A di bawah |
| 3b | Google Drive → **Get file content using id** | File id (fx): `items('Apply_to_each')?['file_id']`. Settings → **Run after**: centang **hanya "Has failed"** pada langkah 3a. |
| 3c | SharePoint → **Create file** | Site: sama. Folder Path (fx): rumus B. File Name (fx): `items('Apply_to_each')?['nama_file']`. File Content: **File Content** dari 3b. |
| 3d | SharePoint → **Update file properties** (opsional) | Library Name: `Documents`. Id: **ItemId** dari 3c. Divisi: `Engineering`. |

Rumus A (path file lengkap, untuk 3a):

```
concat('/Shared Documents/<path folder induk>/Foto WebGIS CWIS-06/', items('Apply_to_each')?['folder'], '/', items('Apply_to_each')?['nama_file'])
```

Rumus B (folder tujuan, untuk 3c):

```
concat('/Shared Documents/<path folder induk>/Foto WebGIS CWIS-06/', items('Apply_to_each')?['folder'])
```

Contoh `<path folder induk>`: `02. PROYEK/2026/<nama proyek>/02. Engineering/09. Dokumentasi`.
Kolom `folder` berisi `2026-11 November/Pekan 2026-11-15 s.d. 2026-11-21/2026-11-20 Jumat`.
SharePoint membuat subfolder yang belum ada.

Cara kerja langkah 3a–3c:
- **File sudah ada**: 3a berhasil, sehingga 3b dan 3c dilewati (*Skipped*).
- **File belum ada**: 3a gagal (*Not found*), lalu 3b dan 3c berjalan dan menyalin foto.

Tanda merah di 3a pada foto baru itu **normal**. Hasil jalan tetap **Succeeded**
selama 3c berhasil.

Terakhir, klik **Save**. Nama langkah perulangan harus tetap **Apply_to_each**
dan langkah 1 harus bernama **Baca antrian**. Kalau nama diganti, sesuaikan rumusnya.

## Langkah 5. Uji

1. Di flow, klik **Test → Manually → Run flow**.
2. Cek SharePoint: di `Foto WebGIS CWIS-06` seharusnya ada folder bulan/pekan/tanggal berisi foto.
3. Jalankan Test sekali lagi: kali ini semua langkah 3b/3c berstatus *Skipped*, karena foto sudah ada.

## Pemantauan harian

| Yang dicek | Di mana | Normalnya |
|---|---|---|
| Foto masuk antrian | Apps Script → ikon **Eksekusi** | `isiAntrianSP` tiap 15 menit, status Selesai |
| Isi file JSON | Apps Script → Log eksekusi `isiAntrianSP` | `File JSON (...): N foto, 7 hari terakhir` |
| Flow berjalan | Power Automate → My flows → flow → 28-day run history | Succeeded tiap 30 menit |
| Foto tersalin | SharePoint › Foto WebGIS CWIS-06 | Ada folder tanggal terbaru |

## Fungsi bantu di Antrian.gs

| Fungsi | Kegunaan |
|---|---|
| `siapkanAntrianSP` | Sekali di awal: membuat tab antrian dan mengisi foto lama |
| `isiAntrianSP` | Dipanggil pemicu 15 menit. Bisa dijalankan manual untuk uji. |
| `tulisJsonSP` | Menulis ulang `antrian_sharepoint.json` (otomatis dipanggil `isiAntrianSP`) |
| `modeSemuaSP` / `modeNormalSP` | Memasukkan semua foto ke JSON (untuk menyalin ulang foto lama), lalu kembali ke 7 hari terakhir |
| `ulangAntrianSP` | Mengosongkan antrian dan mengisi ulang dari awal |
| `diagnosaAntrianSP` | Bila antrian tetap 0: menampilkan nama tab, judul kolom, dan akses Drive |

## Pemecahan masalah

| Gejala | Penyebab | Solusi |
|---|---|---|
| Jendela izin Apps Script "tidak dapat membuka file" | Browser login beberapa akun Google | Pakai jendela yang hanya login akun KSO |
| `Masuk antrian: 0 foto` | Semua foto sudah ada di antrian, atau judul kolom berbeda | Lihat tab antrian. Bila kosong, jalankan `diagnosaAntrianSP`. |
| Error 429 "Too many requests" pada Google Sheets | Konektor Google Sheets dipanggil terlalu sering | Jangan pakai konektor Google Sheets di flow (versi ini sudah tidak memakainya) |
| Compose error `base64ToString` | Langkah 1 masih Infer Content Type = Yes, atau namanya bukan "Baca antrian" | Set Infer Content Type = No, rename jadi "Baca antrian" |
| Apply to each "Enter a valid array" | Designer menolak rumus langsung | Isi lewat Compose, lalu pilih Outputs Compose |
| Semua foto disalin ulang tiap jalan | Rumus A tidak sama dengan lokasi Create file | Samakan bagian depan rumus A dan B |
| Foto lama tidak ikut tersalin | Lebih dari 7 hari sejak masuk antrian | Jalankan `modeSemuaSP`, tunggu flow selesai, lalu `modeNormalSP` |
| File di SharePoint berstatus *Pending* | Library memakai persetujuan (Approval) | Minta pemilik site menyetujui atau mengecualikan folder |

## Privasi

Nama file foto memuat nama petugas. Folder SharePoint bisa dibuka semua anggota
site. Batasi akses folder bila perlu.
