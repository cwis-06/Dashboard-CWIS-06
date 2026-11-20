# WebGIS Monitoring Pipa Sewerage CWIS 06 - Banjardowo dan Genuksari

Dashboard peta untuk memantau progres pekerjaan pipa lateral dan manhole sewerage Paket CWIS 06.
Dibangun dengan Leaflet, berjalan sepenuhnya di browser, dan dihosting gratis di GitHub Pages.
Datanya berasal dari database PostGIS yang diedit lewat QGIS, lalu diekspor menjadi file GeoJSON di folder `data/`.

Alamat dashboard: https://cwis-06.github.io/Dashboard-CWIS-06/
Repo: https://github.com/cwis-06/Dashboard-CWIS-06

Dokumen ini dibagi dua bagian:

- **Bagian A** untuk semua orang yang hanya ingin melihat dashboard.
- **Bagian B** untuk tim yang memperbarui data, termasuk cara menghubungkan komputer masing-masing.

---

# Bagian A. Menggunakan dashboard

Buka alamat dashboard di browser (Chrome, Edge, Firefox, atau Safari, di komputer maupun HP). Tidak perlu login atau instalasi apa pun.

## Fitur utama

| Fitur | Cara pakai |
|---|---|
| Cari | Ketik ID manhole atau pipa (misalnya `MHJ_06_0752`), nama jalan, atau material di kotak pencarian. Tekan `/` untuk langsung ke kotak cari. |
| Tampilan peta | Tombol **Metode** mewarnai pipa berdasarkan metode (Jacking atau Open Trench). Tombol **Progres** mewarnai berdasarkan persen progres. |
| Layer peta | Nyalakan atau matikan pipa lateral, manhole, pipa collecting, pipa persil, inspection chamber, house inlet, zona, dan batas RW. |
| Peta dasar | Pilih OpenStreetMap, citra satelit Esri, **Ortofoto CWIS-06**, atau tanpa peta dasar. |
| Filter | Saring berdasarkan zona, kelas pipa (Primary, Secondary, Tertiary), dan status (belum mulai, berjalan, selesai). Tombol **Reset** mengembalikan semuanya. |
| Progres per zona | Klik satu zona untuk memfilter dan memperbesar peta ke zona itu. |
| Popup | Klik pipa atau manhole untuk melihat lokasi, elevasi, kedalaman, dan status progres. |
| Ukur jarak dan luas | Klik tombol penggaris di kanan atas peta, pilih **Jarak** atau **Luas**, lalu klik titik demi titik. Hasil tampil di panel. **Urungkan**, **Hapus**, atau **Tutup** (Esc) untuk mengatur ukuran. |
| Kegiatan lapangan | Tanda bulat kecil di dekat manhole atau pipa berarti ada kegiatan di sana (angka = jumlah foto, kuning berdenyut = kegiatan pada tanggal yang dipilih). Klik pipa atau manhole itu untuk melihat dokumentasi fotonya di bagian bawah popup. Bar tanggal di atas peta membatasi tampilan pada **7 hari ke belakang** dari tanggal yang dipilih. Tombol **Terbaru** menampilkan daftar kegiatan. Petugas mengunggah lewat tombol **Foto** (lihat Bagian B8). |
| Panduan | Tombol **Panduan** di header membuka tutorial langkah demi langkah. Tutorial juga muncul otomatis saat pertama kali dashboard dibuka. |
| GPS | Tombol lokasi di kanan atas peta menampilkan posisi Anda (butuh izin lokasi dari browser). |
| Tema | Tombol **Tema** mengganti mode terang atau gelap. |

## Tips

- **House inlet** (SR, HI, HIP) awalnya tidak ditampilkan. Centang di panel **Layer peta**, lalu perbesar peta sampai zoom 18 supaya titiknya muncul.
- Pipa yang lebih tebal menandakan kelas pipa yang lebih besar.
- Lingkaran putus-putus pada manhole menandakan manhole dari paket sebelah (referensi).
- Di HP, panel kontrol ada di bagian bawah. Tarik gagangnya ke atas untuk membuka panel, dan pakai tombol **Legenda** untuk melihat keterangan warna.
- Jika data tampak lama setelah ada pembaruan, muat ulang dengan **Ctrl+F5** (di HP: tutup tab lalu buka lagi).

## Catatan privasi

Halaman GitHub Pages bersifat publik, termasuk titik House Inlet. Pertimbangkan hal ini sebelum membagikan alamatnya.

---

# Bagian B. Memperbarui data (untuk tim pengelola)

## Cara kerja secara singkat

```
QGIS (edit layer di PostGIS)
   -> Save Edits
   -> update_dashboard.bat (ekspor ke data/*.geojson, lalu git push)
   -> GitHub Pages (dashboard terbarui dalam 1-2 menit)
```

Dashboard tidak membaca database secara langsung. Ia hanya membaca file GeoJSON yang diekspor oleh `update_dashboard.bat`.

## B1. Menghubungkan komputer Anda (sekali saja)

### Yang perlu dipasang

| Aplikasi | Kegunaan | Catatan |
|---|---|---|
| Git for Windows | Sinkron dengan GitHub | Unduh di git-scm.com |
| QGIS | Edit data dan menyediakan `ogr2ogr` untuk ekspor | Harus terpasang di `C:\Program Files\QGIS ...` |
| PostgreSQL (klien `psql`) | Menghitung ulang kolom otomatis sebelum ekspor | Harus terpasang di `C:\Program Files\PostgreSQL\<versi>`. Jika database ada di server lain, cukup pasang komponen Command Line Tools. |
| Akun GitHub | Akses ke repo | Minta pemilik repo menambahkan Anda sebagai collaborator dengan hak tulis (Settings > Collaborators). |

### Langkah 1: Ambil repo ke komputer Anda

Buka Command Prompt, lalu jalankan:

```bat
cd C:\Users\NAMA_ANDA
git clone https://github.com/cwis-06/Dashboard-CWIS-06.git
```

Saat pertama kali push, jendela login GitHub akan muncul. Login satu kali, dan Windows akan mengingatnya. Jika diminta password, gunakan **Personal Access Token** (GitHub > Settings > Developer settings > Personal access tokens), bukan password akun.

Atur nama dan email Git sekali saja, karena dipakai untuk setiap commit:

```bat
git config --global user.name "Nama Anda"
git config --global user.email "email@anda.com"
```

### Langkah 2: Sambungkan ke database

Database yang dipakai adalah PostgreSQL/PostGIS dengan database `db_cwis06`, schema `sewer`.

1. Minta pengelola database untuk alamat server (host), port, nama user, dan password.
2. **Jangan mengubah isi `update_dashboard.bat`.** Salin `config_lokal.contoh.bat` menjadi `config_lokal.bat` di folder yang sama, lalu ubah barisnya (hapus `rem ` di depan baris yang dipakai):

   ```bat
   set DB_HOST=192.168.1.10     rem alamat server bila database ada di komputer lain
   set DB_USER=editor_cwis06    rem nama user Anda
   ```

   `config_lokal.bat` dibaca lewat `_koneksi.bat` (pengaturan koneksi bersama untuk `update_dashboard.bat`, `setup_otomasi.bat`, dan `cek_database.bat`), dan **tidak ikut terunggah** ke GitHub. Jadi pengaturan tiap orang tidak saling menimpa. Bila tidak ada `config_lokal.bat`, dipakai nilai bawaan (`localhost`, `5432`, `db_cwis06`, `postgres`).
3. Di QGIS, tambahkan koneksi PostGIS: **Layer > Add Layer > Add PostGIS Layers > New**, isi host, port, database, user, dan password yang sama.

Jika database ada di komputer lain, komputer itu harus bisa diakses dari jaringan Anda (satu jaringan atau lewat VPN), dan PostgreSQL harus mengizinkan koneksi dari komputer Anda (`listen_addresses` dan `pg_hba.conf`). Hubungi pengelola database untuk ini.

### Langkah 3: Password database

Skrip tidak menyimpan password di dalam file. Ada dua cara:

- **Otomatis (disarankan):** buat file `%APPDATA%\postgresql\pgpass.conf` berisi satu baris:
  ```
  localhost:5432:db_cwis06:postgres:PASSWORD_ANDA
  ```
  Sesuaikan host dan user. Skrip akan membacanya sendiri.
- **Manual:** jika file itu tidak ada, skrip akan menanyakan password setiap dijalankan (input tersembunyi).

### Langkah 4: Pasang otomasi database (sekali per database, bukan per komputer)

Hanya **satu orang** yang perlu menjalankan ini, yaitu pengelola database. Klik dua kali `setup_otomasi.bat` di folder repo, dan ulangi setiap kali `otomasi_qgis_monitor.sql` berubah. Jika Anda hanya mengedit data, lewati langkah ini.

Skrip hanya menjalankan `otomasi_qgis_monitor.sql` (view `v_lateral_pipe`, pemeriksaan kualitas data `qa_report`, riwayat progres `progress_snapshot`) dalam satu transaksi; bila gagal, tidak ada yang berubah.

**Penting:** trigger dan fungsi lain di database (kolom otomatis, validasi tahap, ujung pipa ikut bergeser, pengaman hapus manhole) sudah disesuaikan langsung di database dan berbeda dari file SQL lama. File lama disimpan di `sql/arsip/` hanya sebagai riwayat; **jangan dijalankan** karena akan menimpa versi yang berlaku. Struktur database yang sebenarnya dicatat otomatis oleh `update_dashboard.bat` ke `sql/skema_db_aktual.sql` setiap kali dijalankan.

Sebelum memasang di database yang sudah berjalan, jalankan `cek_database.bat` lebih dulu. Skrip ini hanya membaca database dan menulis hasilnya ke `diagnosa_hasil.txt` (tidak ikut terunggah).

## B2. Alur kerja harian

1. Di QGIS, edit layer di schema `sewer`. Layer yang diedit adalah tabel dasarnya (misalnya `manhole` dan `lateral_pipe`), sedangkan yang ditampilkan di dashboard adalah view `v_manhole` dan `v_lateral_pipe`.
2. Klik **Save Edits**. Tanpa ini perubahan tidak masuk ke database, jadi dashboard tidak berubah.
3. Klik dua kali `update_dashboard.bat` di folder repo.
4. Skrip melakukan berurutan:
   1. sinkron dengan GitHub,
   2. menghitung ulang kolom otomatis (`refresh_all`); bila gagal, proses berhenti,
   3. **memeriksa kualitas data** (`qa_report`); temuan level ERROR menghentikan unggahan (lihat B2a),
   4. menyimpan **riwayat progres hari ini** per zona (`progress_snapshot`) dan **struktur database yang berlaku** ke `sql/skema_db_aktual.sql`,
   5. mengekspor semua layer ke `data/*.geojson` dan riwayat ke `data/progress_history.csv`,
   6. commit lalu push. Bila push ditolak karena ada pembaruan dari komputer lain, skrip menyesuaikan, mengekspor ulang, lalu mencoba lagi (sampai 3 kali).
5. Tunggu 1-2 menit, buka dashboard, lalu tekan **Ctrl+F5**.

Aturan agar tidak bentrok:

- Sebaiknya jangan menjalankan `update_dashboard.bat` bersamaan dengan orang lain. Di satu komputer, skrip menolak jalan dua kali sekaligus. Antarkomputer, push yang ditolak ditangani dengan sinkron dan ekspor ulang.
- Jika skrip berhenti dengan tulisan konflik, jangan lanjutkan. Hubungi pengelola repo.
- Pastikan semua orang mengedit **database yang sama**. Kalau tiap orang punya salinan database sendiri, data di GitHub akan saling menimpa.

## B2a. Pemeriksaan kualitas data

Setiap kali dijalankan, `update_dashboard.bat` menampilkan daftar temuan dari `sewer.qa_report()`:

| Level | Contoh pemeriksaan | Akibat |
|---|---|---|
| ERROR | Manhole hulu/hilir pipa tidak ada, `stage_code` tidak terdaftar di `ref_stage`, objek tanpa geometri | Unggahan **dihentikan**. Perbaiki di QGIS, Save Edits, lalu jalankan lagi. |
| PERINGATAN | Tanggal aktual di masa depan, sudah ada tahap tetapi `actual_date` kosong, pipa collecting belum tersambung, ID IC sementara (`TMP`) | Unggahan tetap jalan. |
| INFO | Pipa atau manhole tanpa `plan_date` | Unggahan tetap jalan. Isi `plan_date` agar kurva S rencana bisa dibuat. |

Daftar lengkapnya bisa dilihat kapan saja di DB Manager QGIS: `SELECT * FROM sewer.qa_report() WHERE n > 0;`

Dalam keadaan darurat, ERROR bisa diturunkan menjadi peringatan dengan `set QA_WAJIB=0` di `config_lokal.bat`. Kembalikan setelah datanya diperbaiki.

## B2b. Riwayat progres

Tabel `sewer.progress_snapshot` menyimpan satu baris per zona per hari (zona `SEMUA` = total paket): jumlah dan panjang pipa, panjang terpasang setara, persen progres pipa, serta jumlah dan rata-rata progres manhole. Bila skrip dijalankan beberapa kali di hari yang sama, baris hari itu ditimpa. Riwayat diekspor ke `data/progress_history.csv` dan bisa dibuka di Excel. Isinya akan dipakai untuk grafik tren dan kurva S di dashboard.

Label **Updated** di dashboard diambil dari `data/meta.json`, yang ditulis skrip hanya bila data berubah, berisi waktu ekspor dan nama operator (`git config user.name`).

## B3. Mengubah progres lewat tabel manhole

Progres manhole bisa diubah langsung di layer `manhole` di QGIS, tanpa upload staging.

| Kolom di `manhole` | Fungsi |
|---|---|
| `stage_code` | Tahap pekerjaan. Hanya kode sah yang diterima (lihat tabel di bawah). |
| `progress_pct` | Persen progres 0-100. |
| `plan_date`, `actual_date` | Tanggal rencana dan tanggal aktual. |

Kode tahap yang sah untuk manhole dan pipa:

| `stage_code` | Label |
|---|---|
| `belum_mulai` | Belum Mulai |
| `galian_shaft` | Galian Shaft |
| `jacking` | Jacking |
| `pemasangan_manhole` | Pemasangan Manhole |
| `pekerjaan_selesai` | Pekerjaan Selesai |

Aturan progres yang tampil di dashboard:

- Jika `progress_pct` diisi (bukan 0 dan bukan kosong), angka itulah yang tampil.
- Jika `progress_pct` kosong atau 0, progres mengikuti bobot standar tahap (`cum_weight` di tabel `ref_stage`).
- Mengganti `stage_code` tidak otomatis mengubah `progress_pct` yang sudah diisi manual. Kosongkan atau perbarui angkanya juga.
- Mengisi `stage_code` dengan kode yang tidak terdaftar akan ditolak saat Save Edits, dengan pesan "Tahap ... tidak sah".

Agar mudah dipakai di QGIS, atur form layer `manhole` (Properties > Attributes Form): `stage_code` dengan widget **Value Relation** ke layer `ref_stage` (Key `stage_code`, Value `stage_label`, filter `"asset_type" = 'manhole' AND "method" = 'ALL'`), `progress_pct` dengan widget **Range** 0-100, dan tanggal dengan widget **Date/Time**.

Catatan untuk pipa: `pipe_id` terisi otomatis dengan pola `from_mh>to_mh` saat data baru dibuat. Saat mengubah `pipe_id` secara manual, pastikan tetap cocok dengan pasangan manholenya.

## B4. Ortofoto (peta dasar dari TIFF)

TIFF tidak bisa ditampilkan langsung oleh browser, dan GitHub menolak file di atas 100 MB. Jadi TIFF diubah dulu menjadi tile gambar kecil.

1. Di QGIS: **Processing Toolbox > Raster tools > Generate XYZ tiles (Directory)**.
2. Isi: extent dari layer TIFF, zoom minimum 12 dan maksimum 20, format **JPG**, dan folder keluaran `tiles\ortho` di dalam folder repo.
3. Struktur hasilnya harus `tiles/ortho/{z}/{x}/{y}.jpg`. Dashboard meminta tepat format dan jalur ini.
4. Push tile secara manual, jangan lewat `update_dashboard.bat`, karena jumlahnya ribuan file:
   ```bat
   cd C:\Users\NAMA_ANDA\Dashboard-CWIS-06
   git add tiles/ortho/12 tiles/ortho/13 tiles/ortho/14 tiles/ortho/15
   git commit -m "Tile ortho zoom 12-15"
   git push
   ```
   Ulangi untuk zoom 16-17 dan 18-20.
5. Di dashboard, pilih **Peta dasar > Ortofoto CWIS-06**. Ortofoto tampil sendiri (tanpa OpenStreetMap), jadi area di luar cakupan TIFF kosong dan tile baru muncul mulai zoom 12.

File `.tif` dan `.tiff` diabaikan oleh git (lihat `.gitignore`) supaya TIFF asli tidak ikut terunggah. Jika ukuran folder tile melebihi sekitar 500 MB, kurangi zoom maksimum.

## B5. Mengunggah perubahan selain data

`update_dashboard.bat` meng-commit `data/`, `index.html`, `README.md`, `js/`, `css/`, `img/`, `foto/`, `sql/`, `.gitignore`, serta file `.sql` dan `.bat` di folder utama. `config_lokal.bat` dan `diagnosa_hasil.txt` tidak pernah ikut. Hanya **tile ortofoto** (`tiles/`) yang tetap dikirim manual (lihat B4). Untuk mengirim perubahan tanpa menjalankan ekspor:

```bat
cd C:\Users\NAMA_ANDA\Dashboard-CWIS-06
git add -A
git commit -m "Pesan perubahan"
git pull --rebase --autostash
git push
```

## B6. Pemecahan masalah

| Gejala | Penyebab dan solusi |
|---|---|
| Dashboard tidak berubah setelah update | Pastikan sudah **Save Edits** di QGIS, lalu cek pesan "Tidak ada perubahan data baru". Muat ulang dengan Ctrl+F5 dan tunggu 1-2 menit. |
| Peta kosong, panel menunjukkan "-" dan 0% | Ada error JavaScript atau file data tidak termuat. Buka F12 > Console dan lihat pesan merahnya. Pastikan `data/v_lateral_pipe.geojson` dan `data/v_manhole.geojson` ada. |
| Layer baru tidak muncul | Layer opsional hanya muncul bila file GeoJSON-nya ada di `data/`. Cek pesan "Dilewati" saat skrip berjalan. |
| `Folder ini bukan repo Git` | `update_dashboard.bat` harus berada di folder hasil `git clone`, satu folder dengan `index.html`. |
| `QGIS tidak ditemukan` | QGIS dicari di `C:\Program Files\QGIS ...`. Jika di lokasi lain, isi `QGIS_DIR` di `config_lokal.bat`. |
| `psql tidak ditemukan` | Skrip berhenti, karena psql dibutuhkan untuk penghitungan ulang dan pemeriksaan data. Pasang PostgreSQL Command Line Tools, atau isi `PSQL` di `config_lokal.bat`. |
| `[2/6] ... Gagal` atau langkah 3 berhenti | Otomasi database belum terpasang atau versinya lama. Jalankan `setup_otomasi.bat`. |
| `Ada ... jenis temuan ERROR` | Baca daftar temuan di atasnya (kolom terakhir berisi contoh ID), perbaiki di QGIS, Save Edits, lalu jalankan lagi. |
| `sedang berjalan di jendela lain` | Ada jendela update lain yang masih terbuka. Bila tidak ada, hapus file kunci yang disebutkan; kunci yang lebih dari 30 menit dihapus otomatis. |
| `Push ditolak 3 kali` atau `fetch first` | Ada commit baru dari orang lain. Jalankan `git pull --rebase --autostash`, lalu `git push`. |
| `file exceeds GitHub's file size limit of 100 MB` | Ada file besar (biasanya TIFF) ikut ter-commit. Pastikan `.gitignore` berisi `*.tif` dan `*.tiff`, lalu batalkan commit dengan `git reset --soft HEAD~1`. |
| `Authentication failed` atau `403` | Login GitHub kedaluwarsa atau tidak punya hak tulis. Login ulang, atau gunakan Personal Access Token. |
| Ortofoto tidak muncul (404 di tab Network) | Format dan jalur tile harus `tiles/ortho/{z}/{x}/{y}.jpg`. Cek ekstensi (`.jpg`, bukan `.png`) dan zoom 12-20 di folder `tiles/ortho`. |
| Save Edits di QGIS ditolak: "Tahap ... tidak sah" | `stage_code` tidak ada di tabel `ref_stage`. Pilih dari dropdown atau gunakan salah satu kode di tabel B3. |

## B7. Pengaturan yang bisa disesuaikan

| Pengaturan | Lokasi |
|---|---|
| Alamat Apps Script untuk foto | `FOTO_URL` di awal `js/app.js` |
| Zoom mulai tampil house inlet | `HI_MINZ` di awal `js/app.js` (default 18) |
| Daftar manhole paket sebelah | Daftar `REF` di `js/app.js`, atau kolom `is_reference` di database |
| Koneksi database, lokasi QGIS/psql, `QA_WAJIB` | `config_lokal.bat` (salin dari `config_lokal.contoh.bat`) |
| SRID sumber | `SRC_SRID` di awal `update_dashboard.bat` (jangan diubah, UTM 49S) |
| Warna, huruf, tata letak | `css/style.css` |
| Jalur dan zoom tile ortofoto | Baris `ortho` di `js/app.js` |

## B8. Foto dokumentasi lapangan

Petugas lapangan bisa mengunggah foto langsung dari HP. Foto disimpan di Google Drive, lokasinya dicatat di Google Sheet, dan dashboard menampilkannya sebagai ikon kamera di peta. Tidak perlu menyentuh repo setiap ada foto baru.

```
HP petugas (dashboard, tombol "Foto")
   -> Google Apps Script (foto/Code.gs)
        -> menyimpan foto ke folder Google Drive
        -> mencatat lokasi dan keterangan di Google Sheet
   <- dashboard membaca daftar foto dari Apps Script dan menampilkannya di peta
```

### Pemasangan (sekali, oleh pengelola)

1. **Buat folder Google Drive** untuk foto, misalnya `Foto Dokumentasi CWIS-06`. Klik kanan foldernya > **Bagikan** > Akses umum > **Siapa saja yang memiliki link**, peran **Pelihat**. Lalu salin **ID folder**, yaitu bagian akhir alamat setelah `/folders/`.
2. **Buat Google Sheet baru**, misalnya `Data Foto CWIS-06`. Buka **Extensions > Apps Script** dari dalam Sheet itu. Jika Anda terlanjur membuat proyek Apps Script dari tempat lain (script.google.com atau Drive), isi `SHEET_ID` pada langkah 4.
3. Hapus isi editor, lalu tempel seluruh isi `foto/Code.gs` dari repo ini. Di repo, `FOLDER_ID`, `SHEET_ID`, dan `KODE_AKSES` sengaja dikosongkan; isi hanya di editor Apps Script.
4. Di bagian atas script, isi pengaturan berikut:
   - `FOLDER_ID`: ID folder dari langkah 1.
   - `SHEET_ID`: ID Google Sheet (bagian alamat di antara `/d/` dan `/edit`). Kosongkan hanya jika script dibuat lewat menu Extensions di dalam Sheet.
   - `KODE_AKSES`: kode rahasia yang diketik petugas. Pilih kode yang tidak mudah ditebak. Untuk beberapa tim, pakai daftar kode (lihat "Kode akses per tim" di bawah).
5. Pilih fungsi `setup` di menu atas editor, klik **Run**, lalu setujui izin akses yang diminta (Drive dan Sheets). Sheet bernama `Dokumentasi Lapangan` akan terisi judul kolom.
6. Klik **Deploy > New deployment**, pilih jenis **Web app**, lalu isi:
   - Execute as: **Me**
   - Who has access: **Anyone**
7. Klik **Deploy** dan salin **Web app URL** (berakhiran `/exec`).
8. Di `js/app.js`, isi baris di bagian atas file:
   ```js
   const FOTO_URL='https://script.google.com/macros/s/XXXX/exec';
   ```
9. Kirim perubahan ke GitHub (`git add -A`, `git commit`, `git push`), lalu muat ulang dashboard dengan Ctrl+F5. Tombol **Foto** dan layer **Foto dokumentasi** akan muncul.

Jika `FOTO_URL` dikosongkan, fitur foto tidak tampil sama sekali.

### Cara petugas memakai

1. Buka dashboard di HP, atau langsung lewat tautan `https://cwis-06.github.io/Dashboard-CWIS-06/#unggah` (tautan ini bisa disimpan sebagai bookmark atau dijadikan QR code).
2. Ketuk tombol **Foto** di kanan atas peta. Izinkan akses lokasi dan kamera bila diminta.
3. Isi **nama petugas** dan **kode akses**. Keduanya diingat di HP itu untuk lain kali.
4. Isi **ID manhole atau pipa** (opsional, ada saran otomatis), **tanggal kegiatan** (otomatis hari ini, boleh sampai 60 hari ke belakang), dan **keterangan kegiatan**, misalnya "Pekerjaan grouting".
5. Ketuk **Ambil foto** (atau **Pilih dari galeri**), lalu tunggu status lokasi menunjukkan GPS didapat.
6. Ketuk **Unggah**. Peta otomatis memperbesar ke lokasi foto yang baru.

Soal lokasi:

- **Ambil foto langsung di lokasi** dan pilih "Lokasi saya sekarang (GPS)". Ini cara paling akurat.
- Untuk **foto dari galeri**, GPS yang terbaca adalah posisi petugas saat mengunggah, bukan posisi saat memotret. Isi ID manhole atau pipa, lalu pilih "Titik manhole/pipa di atas" supaya foto ditempatkan di titik itu.
- Foto otomatis diperkecil di HP sebelum dikirim (sisi terpanjang 1600 px), jadi hemat kuota dan cepat.

### Struktur folder rekap di Drive

Setiap foto otomatis disimpan di folder `Rekap Foto` (di dalam folder induk Anda) dengan susunan bulan, pekan, dan hari. Folder dibuat sendiri bila belum ada:

```
Rekap Foto/
  2026-11 November/
    Pekan 2026-11-14 s.d. 2026-11-20/        (pekan berjalan Sabtu sampai Jumat)
      2026-11-17 Selasa/
        20261117_145700_MHJ_06_0753_Fiqri.jpg
```

- Folder ditentukan oleh **tanggal kegiatan** yang dipilih petugas, bukan jam unggah.
- Pekan yang melintasi dua bulan (misalnya Sabtu 28 Nov sampai Jumat 4 Des) muncul di kedua folder bulan sesuai tanggal fotonya.
- Zona waktu memakai WIB (`ZONA_WAKTU` di `Code.gs`).
- Foto lama yang diunggah sebelum fitur ini bisa dirapikan dengan menjalankan fungsi `susunUlang` sekali dari editor Apps Script.

Di Google Sheet, tiap baris foto juga mencatat kolom `tanggal`, `pekan`, `bulan`, dan `link_foto`. Tab **Rekap** (dibuat oleh `setup`) menghitung otomatis jumlah foto per hari, per pekan, dan per bulan.

### Tampilan kegiatan di dashboard

- **Bar tanggal** di atas peta: pilih tanggal akhir lewat kalender, tanda panah, atau tombol **Hari ini**. Peta hanya menampilkan kegiatan **7 hari ke belakang** dari tanggal itu.
- **Tanda kegiatan**: bulat kecil yang bergeser sedikit dari titik manhole atau pipa. Angka menunjukkan jumlah foto. Warna kuning berdenyut berarti ada kegiatan pada tanggal yang dipilih, dan tanda polos berarti kegiatan di hari-hari sebelumnya dalam rentang itu.
- **Popup pipa atau manhole**: bagian **Dokumentasi kegiatan** di bagian bawah memuat keterangan, waktu, petugas, dan gambar kecil. Ketuk satu baris untuk membuka foto ukuran besar dengan keterangan lengkap, dan gunakan tombol Sebelumnya dan Berikutnya untuk berpindah foto.
- **Pengaitan foto**: foto dikaitkan ke manhole atau pipa lewat ID yang diisi petugas. Bila ID kosong atau salah, dipakai manhole terdekat dalam radius 25 m. Foto yang jauh dari manhole manapun tampil sebagai tanda di titik GPS-nya.
- Layer **Tanda kegiatan lapangan** di panel Layer peta bisa dimatikan.

### Kegiatan terbaru

Tombol **Terbaru** di kanan atas peta membuka daftar kegiatan pada rentang 7 hari yang sedang dipilih, dikelompokkan per hari. Setiap baris menampilkan **keterangan kegiatan** lebih dulu, lalu ID, jam, dan petugas, dengan gambar kecil di sisi kanan. Mengetuk teksnya memperbesar peta ke lokasi kegiatan dan membuka popupnya. Mengetuk gambar kecilnya membuka foto ukuran besar. Jendela ini juga muncul otomatis sekali per sesi saat dashboard dibuka (kecuali saat panduan pertama kali tampil). Untuk mematikannya, ubah `FOTO_AUTO` di awal `js/app.js` menjadi `false`.

### Kode akses per tim

`KODE_AKSES` bisa berupa daftar, sehingga tiap tim punya kode sendiri:

```js
const KODE_AKSES = { 'kode-tim-a': 'Tim Genuk', 'kode-tim-b': 'Kontraktor', 'kode-tim-c': 'Konsultan' };
```

Nama tim dicatat di kolom `tim` pada Sheet dan tampil di daftar foto terbaru. Jika ada lebih dari satu tim, muncul pilihan untuk menampilkan foto dari tim tertentu saja. Kode yang diketik petugas tidak pernah disimpan atau ditampilkan, hanya nama timnya. Cabut akses suatu tim dengan menghapus kodenya dari daftar, lalu deploy versi baru.

### Di mana keterangan tersimpan

Keterangan yang diisi petugas tersimpan di dua tempat: kolom `keterangan` pada Google Sheet (bersama petugas, ID, koordinat, tanggal, dan waktu), dan deskripsi file di Google Drive (klik kanan file > Detail). Keterangan juga tampil di popup pipa atau manhole, di penampil foto, dan di daftar kegiatan terbaru.

### Mengelola foto

- **Menyembunyikan foto** dari peta: di Google Sheet `Foto`, ubah kolom `tampil` dari TRUE menjadi FALSE. File di Drive tetap ada. Perubahan tampil dalam sekitar 1 menit.
- **Mengubah kode akses**: ubah `KODE_AKSES` di Apps Script, lalu **Deploy > Manage deployments > Edit (ikon pensil) > Version: New version > Deploy**. Alamat web app tetap sama.
- **Setiap perubahan isi script** perlu langkah "New version" di atas supaya berlaku, dan jalankan `setup` sekali lagi setelah menempel `Code.gs` baru (menambah kolom `tanggal`, `pekan`, `bulan`, `link_foto` dan tab Rekap).
- Foto dan Sheet ada di akun Google pembuat script, jadi gunakan akun milik tim yang akan terus dipakai, bukan akun pribadi yang bisa berhenti dipakai.

### Hal yang perlu diperhatikan

- **Foto bersifat publik.** Agar bisa tampil di dashboard, file di Drive dibagikan sebagai "siapa saja yang memiliki tautan", dan dashboard sendiri publik. Hindari memotret wajah orang atau plat nomor. Nama petugas dan keterangan juga ikut tampil di popup.
- **Kode akses melindungi unggahan**, bukan tampilan. Orang yang tidak punya kode tidak bisa menambah foto, tetapi siapa pun yang membuka dashboard bisa melihat foto yang sudah ada.
- Kode akses tidak disimpan di repo, tetapi tersimpan di `Code.gs` pada akun Apps Script Anda. Jangan menempelkannya ke `app.js`.
- Jika akun Google Anda berada di Google Workspace organisasi, administrator mungkin membatasi pembagian file atau akses "Anyone". Bila foto tidak tampil di dashboard, periksa pengaturan itu.
- Penyimpanan Drive dihitung dari akun pembuat. Satu foto setelah diperkecil biasanya 300-600 KB.
- Pengunggahan butuh **https** dan sinyal. Bila gagal di tengah jalan, foto yang sudah terkirim tidak diulang, dan sisanya tetap ada di formulir untuk dicoba lagi.

### Pemecahan masalah foto

| Gejala | Penyebab dan solusi |
|---|---|
| Tombol Foto tidak muncul | `FOTO_URL` di `app.js` masih kosong, atau perubahan belum ter-push. |
| `Cannot read properties of null (reading 'getSheetByName')` saat menjalankan `setup` | Script tidak terhubung ke Google Sheet. Isi `SHEET_ID` lalu jalankan `setup` lagi. |
| "Kode akses salah" | Kode di formulir berbeda dengan `KODE_AKSES` di Apps Script. Periksa spasi di awal atau akhir. |
| "Gagal mengunggah" tanpa pesan jelas | Sinyal lemah, atau deployment Web app bukan "Anyone". Cek pengaturan deploy dan coba buka alamat `/exec` di browser. Hasilnya harus berupa teks JSON (misalnya `[]`). |
| Foto terunggah tapi ikon tidak muncul | Tunggu 1 menit lalu muat ulang. Cek kolom `tampil` di Sheet dan pastikan layer "Foto dokumentasi" tercentang. |
| `Access denied: DriveApp` saat mengunggah | Google menolak pembagian file otomatis. Versi script terbaru tetap berhasil menyimpan. Bagikan **folder** Drive sebagai "Siapa saja yang memiliki link - Pelihat" supaya semua foto di dalamnya terbaca dashboard. |
| Ikon muncul tapi gambar kosong di popup | File di Drive belum dibagikan sebagai "siapa saja dengan tautan" (sering karena pembatasan Workspace). |
| GPS tidak tersedia | Aktifkan GPS dan izin lokasi untuk browser, atau pakai titik manhole atau pipa. |

## Struktur folder

```
Dashboard-CWIS-06/
  index.html              kerangka halaman
  css/style.css           tampilan (warna, huruf, mode gelap)
  js/app.js               logika peta, filter, popup
  data/*.geojson          hasil ekspor database (jangan diedit tangan)
  data/meta.json          waktu ekspor terakhir dan operator (ditulis skrip)
  data/progress_history.csv  riwayat progres harian per zona (ditulis skrip)
  img/                    logo header dan favicon
  foto/Code.gs            backend foto dokumentasi (disalin ke Google Apps Script, tidak dijalankan di GitHub)
  tiles/ortho/            tile ortofoto (z/x/y.jpg)
  otomasi_qgis_monitor.sql  view pipa, pemeriksaan data, riwayat progres
  sql/skema_db_aktual.sql struktur database yang berlaku + isi ref_stage (ditulis skrip)
  sql/isi_plan_date_msp.sql  tanggal rencana dari MSP dan urutan jacking Zona 2 (dijalankan manual)
  sql/diagnosa.sql        query baca-saja untuk cek_database.bat
  sql/arsip/              skema awal, migrasi, dan otomasi lama; hanya riwayat, jangan dijalankan
  _koneksi.bat            pengaturan koneksi bersama (dipanggil skrip lain, tidak dijalankan sendiri)
  setup_otomasi.bat       pasang otomasi_qgis_monitor.sql (oleh pengelola database)
  cek_database.bat        baca struktur database ke diagnosa_hasil.txt (tidak mengubah apa pun)
  update_dashboard.bat    hitung ulang, periksa data, ekspor, dan push ke GitHub
  config_lokal.contoh.bat contoh pengaturan lokal (salin menjadi config_lokal.bat)
  .gitignore              mengabaikan TIFF, config_lokal.bat, diagnosa_hasil.txt, file sementara
```

## Data

Wajib ada: `v_lateral_pipe.geojson` dan `v_manhole.geojson`.
Opsional (layer muncul otomatis bila filenya ada): `house_inlet`, `inspection_chamber`, `collecting_pipe`, `persil_pipe`, `zona`, `batas_rw`. Semuanya `.geojson` dengan sistem koordinat EPSG:4326.

Cara manual tanpa skrip: ekspor layer dari QGIS ke GeoJSON (EPSG:4326, nama file sama persis), lalu di GitHub buka folder `data` > Add file > Upload files > Commit changes.
