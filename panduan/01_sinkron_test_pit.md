# 01. Sinkron test pit dari Google Sheet ke WebGIS

## Tujuan

Tim lapangan cukup mengisi tab **TEST PIT** di Google Sheet. Setiap kali
`update_dashboard.bat` dijalankan, isi Sheet ikut masuk ke database dan peta,
tanpa mengetik ulang di QGIS.

## Cara kerja

```
Google Sheet (tab TEST PIT)
   │  1. sinkron\ambil_sheet_testpit.ps1
   │     unduh CSV, ambil kolom yang dipakai berdasarkan judul kolom
   v
%TEMP%\cwis06_tp_sheet.csv
   │  2. psql \copy
   v
staging.tp_sheet            (isi mentah, dikosongkan tiap kali)
   │  3. SELECT * FROM sewer.sinkron_test_pit();
   v
sewer.test_pit              (tabel yang tampil di peta)
   │  4. ekspor seperti biasa
   v
data/test_pit.geojson  ->  WebGIS
```

Langkah 1 sampai 3 adalah langkah **[2/7]** di `update_dashboard.bat`.
Bila langkah ini gagal (internet putus, Sheet tidak bisa dibuka), update tetap
berlanjut memakai isi database yang ada, dan muncul tulisan **Peringatan**.

## File yang terlibat

| File | Isi | Di repo? |
|---|---|---|
| `sinkron/ambil_sheet_testpit.ps1` | Unduh Sheet, pilih kolom, tulis CSV rapi | ya |
| `sql/sinkron_test_pit.sql` | Tabel `staging.tp_sheet` dan fungsi `sewer.sinkron_test_pit()` | ya |
| `update_dashboard.bat` | Menjalankan sinkron di langkah [2/7] (subrutin `:sinkron_testpit`) | ya |
| `setup_otomasi.bat` | Memasang `sql/sinkron_test_pit.sql` ke database | ya |
| `_koneksi.bat` | Nilai bawaan `TP_SHEET_ID` (kosong) dan `TP_SHEET_GID` (0) | ya |
| `config_lokal.bat` | **ID Sheet** milik proyek | **tidak** (rahasia) |

## Pemasangan (sekali)

### Langkah 1. Pastikan Sheet bisa dibaca lewat tautan

Buka Sheet test pit, klik **Share/Bagikan**, lalu di **General access** pilih
**Anyone with the link** dengan peran **Viewer**.

Catatan keamanan: siapa pun yang tahu tautannya bisa melihat Sheet. Karena itu
ID Sheet tidak ditaruh di repo publik, hanya di `config_lokal.bat`.

### Langkah 2. Catat ID Sheet dan GID tab TEST PIT

Buka tab TEST PIT. Alamatnya berbentuk:

```
https://docs.google.com/spreadsheets/d/  1AbC...xyz  /edit#gid=  0
                                         └── ID ──┘            └GID┘
```

### Langkah 3. Isi `config_lokal.bat` di folder repo

Kalau file ini belum ada, salin `config_lokal.contoh.bat` lalu ganti namanya
menjadi `config_lokal.bat`. Tambahkan dua baris (tanpa `rem`):

```bat
set TP_SHEET_ID=1AbC...xyz
set TP_SHEET_GID=0
```

Setiap komputer yang menjalankan `update_dashboard.bat` perlu langkah ini.

### Langkah 4. Pasang fungsi sinkron ke database

Klik dua kali `setup_otomasi.bat`. Script ini aman diulang. Ia memasang
`sql/sinkron_test_pit.sql` bersama file otomasi lain.
Cukup sekali per database, bukan per komputer.

### Langkah 5. Uji

Klik dua kali `update_dashboard.bat`, lalu baca bagian langkah [2/7]. Contoh:

```
[2/7] Sinkron test pit dari Google Sheet ...
  215 baris test pit diunduh dari Sheet.
Baris test pit terbaca dari Sheet | 215 |
Status berubah | 2 | TP 05 Direncanakan -> Selesai, TP 12 Direncanakan -> Digali
Titik diperbarui (semua kolom) | 3 |
```

## Pemakaian harian

1. Isi atau ubah baris di tab TEST PIT. Misalnya Status jadi `SELESAI`, lalu
   isi tanggal pelaksanaan, utilitas yang ditemukan, mandor, dan link BA.
2. Jalankan `update_dashboard.bat`.
3. Buka dashboard, aktifkan layer **Test pit**, lalu tekan Ctrl+F5.

## Aturan pengisian Sheet

| Kolom (judul di Sheet) | Wajib | Contoh | Catatan |
|---|---|---|---|
| No. Test Pit | ya | `TP 01` | Kunci pencocokan. Angkanya yang dipakai (TP 01 = TP 1). |
| Status | ya | `SELESAI` | Lihat tabel status di bawah. |
| No. Manhole | untuk TP baru | `MH_06_0752` | TP baru diletakkan di posisi manhole ini. |
| Zona | tidak | `2` | |
| Utilitas yang Ditemukan | tidak | `PDAM HDPE 3"` | `TIDAK ADA UTILITAS` disimpan sebagai "Tidak ada utilitas". |
| Jenis Permukaan | tidak | `PAVING BLOCK` | Disimpan sebagai "Paving block". |
| Tanggal Pelaksanaan | tidak | `26/07/2026` | Format hari/bulan/tahun atau `2026-07-26`. |
| Link Dokumentasi BA Testpit | tidak | tautan Drive | |
| MANDOR | tidak | `RICARDO` | |

- Script mengenali kolom dari **judulnya**, bukan urutannya. Kolom boleh
  digeser atau ditambah, asalkan judul di atas tidak diganti. Huruf besar/kecil,
  spasi, dan titik diabaikan.
- Baris judul boleh berada di salah satu dari 15 baris pertama.
- Baris yang kolom No. Test Pit-nya tidak berisi angka (baris kosong, baris
  total) dilewati.
- Kolom koordinat di Sheet **tidak dipakai**. Posisi titik diatur di QGIS
  atau dari manhole acuan.

Teks status yang dikenali (tidak peka huruf besar/kecil):

| Tulisan di Sheet mengandung | Menjadi |
|---|---|
| belum, rencana | Direncanakan |
| selesai, sudah, done | Selesai |
| tunda, pending, batal | Ditunda |
| gali, proses, berjalan, progres | Digali |
| kosong | tidak mengubah status |

## Aturan sinkron (apa yang ditimpa dan apa yang tidak)

1. **Status hanya naik**: Direncanakan → Ditunda → Digali → Selesai.
   Kalau Sheet menulis status yang lebih rendah dari database (misalnya Sheet
   "BELUM" padahal database "Selesai"), status tidak diturunkan dan baris itu
   dilaporkan supaya dicek.
2. **Tanggal, utilitas, permukaan, mandor, link BA**: isi Sheet yang tidak
   kosong **menimpa** database. Sel kosong di Sheet tidak menghapus isi database.
   Artinya, untuk kolom ini Sheet adalah sumber utama. Perbaikan cukup di Sheet.
3. **Manhole acuan dan zona** hanya diisi bila di database masih kosong.
4. **Posisi titik tidak pernah diubah** oleh sinkron.
5. **Nomor TP yang belum ada di database** ditambahkan otomatis di posisi
   manhole acuannya. Bila manhole tidak ditemukan, baris dilewati dan dilaporkan.
6. Titik yang ada di database tetapi tidak ada di Sheet **tidak disentuh**.
7. Bila satu nomor TP muncul dua kali di Sheet, yang dipakai baris paling atas.

## Membaca laporan sinkron

| Baris laporan | Arti | Tindakan |
|---|---|---|
| Baris test pit terbaca dari Sheet | Jumlah baris valid di Sheet | - |
| Status berubah | Daftar TP yang statusnya naik | - |
| Titik diperbarui (semua kolom) | Jumlah TP yang ada perubahannya | - |
| Titik baru ditambahkan | Nomor TP baru yang masuk peta | Cek posisinya di peta |
| PERIKSA: TP baru dilewati (manhole tidak ditemukan) | No. Manhole kosong atau salah ketik | Perbaiki di Sheet, atau tambahkan titiknya di QGIS |
| PERIKSA: status Sheet lebih rendah dari database | Sheet dan database berbeda | Tentukan mana yang benar, lalu samakan |
| PERIKSA: tanggal tidak terbaca | Format tanggal salah | Ubah ke `26/07/2026` |

Baris yang jumlahnya 0 tidak ditampilkan.

## Pemecahan masalah

| Pesan | Penyebab | Solusi |
|---|---|---|
| `Dilewati: TP_SHEET_ID belum diisi di config_lokal.bat` | Langkah 3 belum dilakukan di komputer ini | Isi `config_lokal.bat` |
| `Yang terunduh halaman login, bukan isi Sheet` | Sheet tidak dibagikan lewat tautan, atau ID/GID salah | Ulangi langkah 1 dan 2 |
| `Kolom "No. Test Pit" dan "Status" tidak ditemukan` | Judul kolom diganti, atau GID menunjuk tab lain | Kembalikan judul kolom, atau periksa `TP_SHEET_GID` |
| `Peringatan: Sheet test pit gagal diunduh` | Tidak ada internet, atau Google sedang bermasalah | Coba lagi nanti. Data lain tetap terunggah. |
| `relation "staging.tp_sheet" does not exist` / `function sewer.sinkron_test_pit() does not exist` | Fungsi belum dipasang | Jalankan `setup_otomasi.bat` |
| Status di peta tidak berubah padahal Sheet sudah "SELESAI" | Tulisan status tidak dikenali, atau langkah [2/7] dilewati | Baca laporan [2/7]. Pastikan sel Status berisi kata "selesai". |

Cek isi database langsung (di pgAdmin atau psql):

```sql
SELECT * FROM staging.tp_sheet LIMIT 20;                 -- isi Sheet terakhir yang terunduh
SELECT * FROM sewer.sinkron_test_pit();                  -- jalankan sinkron manual dan lihat laporannya
SELECT tp_id, status, actual_date, updated_at FROM sewer.test_pit ORDER BY updated_at DESC LIMIT 20;
```

## Replikasi untuk Sheet atau tabel lain

Pola yang sama bisa dipakai untuk bore log atau data lain:

1. Salin `sinkron/ambil_sheet_testpit.ps1`, lalu ubah daftar `$pola` (judul
   kolom yang dicari). Kunci pertama di `$pola` harus kolom pengenal (nomor).
2. Salin `sql/sinkron_test_pit.sql`, lalu ubah tabel staging, kolom, dan
   aturan pembaruan di fungsi.
3. Tambahkan subrutin baru di `update_dashboard.bat` (contoh: `:sinkron_testpit`)
   dan pasang file SQL lewat `setup_otomasi.bat`.
4. Tambahkan ID Sheet baru di `config_lokal.bat`, bukan di repo.
