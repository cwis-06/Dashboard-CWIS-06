# 03. Watermark otomatis pada foto kamera

## Tujuan

Foto yang diambil langsung dari kamera HP lewat WebGIS diberi tanda
(watermark) sebagai bukti waktu dan lokasi. Foto dari galeri tidak diberi
watermark.

## Isi watermark

- Kiri atas: logo gabungan (`img/logo-header.png`) dengan latar putih.
- Bawah, berurutan:
  - hari, tanggal, jam WIB
  - koordinat GPS dan akurasinya (atau "Koordinat tidak tersedia" bila GPS mati)
  - kegiatan (dari kolom keterangan)
  - lokasi (ID manhole atau pipa, bila diisi)
  - nama proyek

Nama petugas sengaja tidak ditulis di foto.

## Cara kerja

1. Di formulir unggah ada dua tombol: **Ambil foto (kamera)** dan **Pilih dari galeri**.
2. Foto dari tombol kamera ditandai `WM` di pratinjau, beserta jam jepret dan GPS saat itu.
   Pengaman: berkas yang dibuat lebih dari 5 menit sebelumnya dianggap foto lama
   dan tidak diberi watermark.
3. Saat **Unggah**, foto diperkecil (sisi terpanjang 1600 px), lalu watermark
   digambar di browser HP. Foto yang dikirim ke Apps Script sudah bertanda.
   Server (`foto/Code.gs`) tidak perlu diubah.
4. Bila ada foto kamera, kolom keterangan kegiatan wajib diisi.

## Lokasi kode (`js/app.js`)

| Bagian | Fungsi / variabel |
|---|---|
| Logo dan nama proyek | `WM_LOGO`, `WM_PROYEK` |
| Menggambar watermark | `wmGambar(canvas, wm)` |
| Memotong teks kegiatan jadi beberapa baris | `wmBaris()` |
| Memperkecil foto lalu memanggil watermark | `fKecil(file, wm)` |
| Menandai foto kamera (jam, GPS) | handler `$('fFc').onchange` |
| Tanda `WM` di pratinjau | `fThumbs()` dan `#fup .fth .wm` di `css/style.css` |

## Mengubah tampilan

- **Ganti logo**: timpa `img/logo-header.png`, atau ubah `WM_LOGO.src`.
- **Ganti nama proyek**: ubah `WM_PROYEK`.
- **Ukuran huruf**: di `wmGambar`, `fs = u*3.1` (3,1% dari sisi terpendek foto).
- **Lebar logo**: di `wmGambar`, `Math.min(W*.5, u*46)`.

Setelah mengubah, jalankan `update_dashboard.bat` (ikut mengunggah `js` dan `css`).

## Uji

1. Buka WebGIS di HP, ketuk **Foto**, lalu **Ambil foto (kamera)**.
2. Pastikan pratinjau bertanda `WM`, isi keterangan, lalu **Unggah**.
3. Buka foto di Drive atau SharePoint, lalu periksa logo, tanggal, koordinat, dan kegiatan.

## Membatalkan

Versi sebelum watermark disimpan di luar repo, di komputer pengelola:
`Downloads\CWIS06_cadangan\sebelum_watermark\` (`app.js`, `style.css`).
Salin ke `js\` dan `css\`, lalu jalankan `update_dashboard.bat`.
