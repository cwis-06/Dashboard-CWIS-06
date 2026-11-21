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
                         (tiap 15 menit) Apps Script Antrian.gs ───┘
                                                                   v
                                                   tab "Antrian SharePoint" (status kosong)
                                                                   │
                         (tiap 30 menit) Power Automate (akun Waskita)
                                                                   v
     SharePoint (site proyek) › … › Foto WebGIS CWIS-06 › bulan › pekan › tanggal
                                                                   │
                                                  status di antrian diisi "selesai"
```

Dari foto diunggah sampai muncul di SharePoint: paling lama sekitar 45 menit.

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
| Flow Power Automate "Salin Foto WebGIS ke SharePoint" | Menyalin foto dan menandai "selesai" (tidak disimpan di repo; dibuat lewat langkah 4) |

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

Tambahkan langkah berikut berurutan. Pada kotak yang ditandai **fx**, klik kotak
itu, ketik `/`, pilih **Insert expression**, lalu tempel rumusnya.

| No | Langkah (konektor → aksi) | Isian |
|---|---|---|
| 1 | Google Sheets → **Get rows** | File: Sheet foto. Worksheet: `Antrian SharePoint`. Login akun Google KSO saat diminta. |
| 2 | Data Operation → **Filter array** | From: `value` dari Get rows. Edit in advanced mode: `@empty(item()?['status'])` |
| 3 | Control → **Apply to each** | Output: ikon petir → **Body** dari Filter array. Jangan pakai rumus `take(...)`, karena ditolak designer baru. |
| 3a | Google Drive → **Get file content using id** (di dalam Apply to each) | File id (fx): `items('Apply_to_each')?['file_id']`. Jangan klik ikon folder. |
| 3b | SharePoint → **Create file** | Site Address: site tujuan. Folder Path (fx): lihat rumus di bawah. File Name (fx): `items('Apply_to_each')?['nama_file']`. File Content: **File Content** dari 3a. |
| 3c | SharePoint → **Update file properties** (opsional) | Site: sama. Library Name: `Documents`. Id: **ItemId** dari 3b. Divisi: `Engineering`. |
| 3d | Google Sheets → **Update row** | File dan Worksheet sama dengan langkah 1. Row id (fx): `items('Apply_to_each')?['__PowerAppsId__']`. status: `selesai`. Kolom lain kosongkan. |

Rumus Folder Path (3b). Ganti bagian depan dengan Path dari langkah 1:

```
concat('/Shared Documents/<path folder induk>/Foto WebGIS CWIS-06/', items('Apply_to_each')?['folder'])
```

Contoh `<path folder induk>`: `02. PROYEK/2026/<nama proyek>/02. Engineering/09. Dokumentasi`.
Path persisnya cukup disimpan di flow, tidak perlu ditulis di repo.

Kolom `folder` di antrian berisi `2026-11 November/Pekan 2026-11-15 s.d. 2026-11-21/2026-11-20 Jumat`.
SharePoint membuat subfolder yang belum ada.

Terakhir, klik **Save**.

Catatan:
- Konektor Google Sheets menambah kolom `__PowerAppsId__` di tab antrian.
  Kolom itu pengenal baris, **jangan dihapus**.
- Nama langkah harus tetap **Apply_to_each** (bawaan). Kalau namanya diganti,
  sesuaikan semua rumus `items('...')`.

## Langkah 5. Uji

1. Di flow, klik **Test → Manually → Run flow**.
2. Cek SharePoint: di `Foto WebGIS CWIS-06` seharusnya ada folder bulan/pekan/tanggal berisi foto.
3. Cek tab Antrian SharePoint: kolom status berisi `selesai`.

## Pemantauan harian

| Yang dicek | Di mana | Normalnya |
|---|---|---|
| Foto masuk antrian | Apps Script → ikon **Eksekusi** | `isiAntrianSP` tiap 15 menit, status Selesai |
| Ringkasan antrian | Apps Script → jalankan `cekAntrianSP` | `belum` mendekati 0 |
| Flow berjalan | Power Automate → My flows → flow → 28-day run history | Succeeded tiap 30 menit |
| Foto tersalin | SharePoint › Foto WebGIS CWIS-06 | Ada folder tanggal terbaru |

## Fungsi bantu di Antrian.gs

| Fungsi | Kegunaan |
|---|---|
| `siapkanAntrianSP` | Sekali di awal: membuat tab antrian dan mengisi foto lama |
| `isiAntrianSP` | Dipanggil pemicu 15 menit. Bisa dijalankan manual untuk uji. |
| `cekAntrianSP` | Ringkasan: total, selesai, belum, gagal |
| `ulangAntrianSP` | Mengosongkan antrian dan mengisi ulang dari awal. Kosongkan dulu folder SharePoint supaya tidak dobel. |
| `diagnosaAntrianSP` | Bila antrian tetap 0: menampilkan nama tab, judul kolom, dan akses Drive |

## Pemecahan masalah

| Gejala | Penyebab | Solusi |
|---|---|---|
| Jendela izin Apps Script "tidak dapat membuka file" | Browser login beberapa akun Google | Pakai jendela yang hanya login akun KSO |
| `Masuk antrian: 0 foto` | Semua foto sudah ada di antrian, atau judul kolom berbeda | Lihat tab antrian. Bila kosong, jalankan `diagnosaAntrianSP`. |
| Apply to each "Enter a valid array" | Designer menolak rumus `take()` | Pakai **Body** dari Filter array lewat ikon petir |
| Get file content gagal | File id berisi path folder, bukan rumus | Isi dengan rumus `items('Apply_to_each')?['file_id']` |
| Create file gagal soal path | Path salah ketik atau ada karakter khusus (mis. `%`) | Pilih folder lewat ikon folder, lalu tambahkan `/` dan `folder` |
| Foto disalin berulang | Langkah 3d (Update row) belum ada atau gagal | Tambahkan atau perbaiki 3d |
| File di SharePoint berstatus *Pending* | Library memakai persetujuan (Approval) | Minta pemilik site menyetujui atau mengecualikan folder |
| Ingin menyalin ulang satu foto | Status sudah "selesai" | Kosongkan sel status foto itu di tab antrian |

## Privasi

Nama file foto memuat nama petugas. Folder SharePoint bisa dibuka semua anggota
site. Batasi akses folder bila perlu.
