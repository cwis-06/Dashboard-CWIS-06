/**
 * Backend dokumentasi kegiatan lapangan - Dashboard GIS CWIS-06
 *
 * Fungsi:
 *  - doPost: menerima foto dari dashboard, menyimpannya ke Google Drive dalam folder otomatis
 *            (bulan > pekan Sabtu-Jumat > hari), lalu mencatat lokasi dan keterangannya di Google Sheet.
 *  - doGet : mengirim daftar kegiatan (JSON) yang dibaca dashboard untuk ditampilkan di peta.
 *
 * Struktur folder di Drive (dibuat otomatis di dalam FOLDER_ID):
 *   Rekap Foto / 2026-11 November / Pekan 2026-11-14 s.d. 2026-11-20 / 2026-11-17 Selasa / foto.jpg
 *
 * Cara pasang: lihat README.md bagian B8.
 */

// ====== PENGATURAN: WAJIB DIISI ======
const FOLDER_ID  = '';   // ID folder induk di Drive (bagian akhir alamat folder)
// Kode yang diketik petugas saat mengunggah. Dua pilihan:
//  1) satu kode untuk semua:   const KODE_AKSES = 'kode-rahasia';
//  2) beberapa kode, tiap kode mewakili satu tim (nama tim ikut tampil di dashboard):
//     const KODE_AKSES = { 'kode-tim-a': 'Tim Genuk', 'kode-tim-b': 'Kontraktor', 'kode-tim-c': 'Konsultan' };
const KODE_AKSES = 'GANTI_DENGAN_KODE_RAHASIA';
const SHEET_ID   = '';   // ID Google Sheet (antara /d/ dan /edit pada alamatnya)
// =====================================

const NAMA_SHEET        = 'Dokumentasi Lapangan';
const NAMA_SHEET_REKAP  = 'Rekap';
const NAMA_FOLDER_REKAP = 'Rekap Foto';
const ZONA_WAKTU        = 'Asia/Jakarta';
const MAKS_BYTE         = 8 * 1024 * 1024;           // batas ukuran foto setelah dikompres di browser
const MAKS_HARI_MUNDUR  = 60;                         // tanggal kegiatan paling lama berapa hari ke belakang
// Kolom A sampai O. Jangan ubah urutannya, karena dashboard dan script membaca berdasarkan posisi kolom.
const HEADERS = ['waktu', 'petugas', 'kode', 'keterangan', 'lat', 'lng', 'akurasi_m', 'sumber_lokasi', 'file_id', 'tampil', 'tim', 'tanggal', 'pekan', 'bulan', 'link_foto'];

const HARI  = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
const BULAN = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

/** Jalankan SEKALI dari editor (tombol Jalankan) untuk memberi izin dan menyiapkan Sheet. Aman diulang. */
function setup() {
  DriveApp.getFolderById(FOLDER_ID);                  // memastikan folder bisa diakses
  const sh = sheet_();
  sh.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);   // menulis ulang judul kolom (data di bawahnya tidak disentuh)
  sh.getRange('L:N').setNumberFormat('@');            // tanggal, pekan, bulan disimpan sebagai teks
  sh.setFrozenRows(1);
  buatRekap_(sh.getParent());
}

/** Opsional, jalankan SEKALI: merapikan foto lama (yang diunggah sebelum fitur folder otomatis) ke struktur folder baru. */
function susunUlang() {
  const sh = sheet_(), data = sh.getDataRange().getValues();
  let n = 0;
  for (let i = 1; i < data.length; i++) {
    const r = data[i], id = r[8];
    if (!id || (r[11] && r[12])) continue;            // sudah tersusun
    try {
      const waktu = r[0] instanceof Date ? r[0] : new Date();
      const tg = tglSel_(r[11], waktu), f = info_(tg);
      DriveApp.getFileById(id).moveTo(folderTujuan_(tg));
      sh.getRange(i + 1, 12, 1, 4).setValues([[tg, f.pekan, f.bulan, linkFoto_(id)]]);
      n++;
    } catch (err) { Logger.log('Baris ' + (i + 1) + ' dilewati: ' + err); }
  }
  CacheService.getScriptCache().remove('daftar');
  Logger.log(n + ' foto disusun ke folder rekap.');
}

// ---------- Pembantu ----------
function sheet_() {
  const ss = SHEET_ID ? SpreadsheetApp.openById(SHEET_ID) : SpreadsheetApp.getActiveSpreadsheet();
  if (!ss) throw new Error('Isi SHEET_ID di bagian pengaturan, karena script ini tidak dibuat dari Google Sheet.');
  return ss.getSheetByName(NAMA_SHEET) || ss.insertSheet(NAMA_SHEET);
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

// Mencegah teks yang diawali = + - @ dibaca sebagai rumus di Google Sheet.
function aman_(s, maks) {
  s = String(s == null ? '' : s).slice(0, maks || 200);
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}

// Mengembalikan nama tim untuk kode akses yang benar, atau null bila kode salah.
function tim_(kode) {
  kode = String(kode == null ? '' : kode);
  if (typeof KODE_AKSES === 'string') return kode === KODE_AKSES ? 'Umum' : null;
  return Object.prototype.hasOwnProperty.call(KODE_AKSES, kode) ? String(KODE_AKSES[kode]) : null;
}

const tglWib_  = d => Utilities.formatDate(d, ZONA_WAKTU, 'yyyy-MM-dd');
const tglUtc_  = d => Utilities.formatDate(d, 'GMT', 'yyyy-MM-dd');
const geser_   = (s, n) => { const p = s.split('-').map(Number); return new Date(Date.UTC(p[0], p[1] - 1, p[2] + n)); };
const linkFoto_ = id => 'https://drive.google.com/file/d/' + id + '/view';

// Tanggal (teks yyyy-MM-dd) dari sel Sheet; bila kosong atau tidak valid, dipakai tanggal dari waktu unggah.
function tglSel_(v, waktu) {
  if (v instanceof Date) return tglWib_(v);
  v = String(v || '');
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  return waktu instanceof Date ? tglWib_(waktu) : tglWib_(new Date());
}

// Informasi hari, pekan (Sabtu sampai Jumat), dan bulan untuk tanggal yyyy-MM-dd.
function info_(s) {
  const p = s.split('-').map(Number);
  const dow = new Date(Date.UTC(p[0], p[1] - 1, p[2])).getUTCDay();   // 0 = Minggu ... 6 = Sabtu
  const sejak = (dow + 1) % 7;                                         // jumlah hari sejak Sabtu terakhir
  return {
    tanggal: s,
    hari: HARI[dow],
    bulan: s.slice(0, 7),
    namaBulan: BULAN[p[1] - 1],
    pekan: tglUtc_(geser_(s, -sejak)) + ' s.d. ' + tglUtc_(geser_(s, 6 - sejak))
  };
}

function folder_(induk, nama) {
  const it = induk.getFoldersByName(nama);
  return it.hasNext() ? it.next() : induk.createFolder(nama);
}

// Folder hari di dalam folder pekan di dalam folder bulan. Dibuat otomatis bila belum ada.
function folderTujuan_(tanggal) {
  const i = info_(tanggal);
  const rekap = folder_(DriveApp.getFolderById(FOLDER_ID), NAMA_FOLDER_REKAP);
  const bulan = folder_(rekap, i.bulan + ' ' + i.namaBulan);
  const pekan = folder_(bulan, 'Pekan ' + i.pekan);
  return folder_(pekan, i.tanggal + ' ' + i.hari);
}

// Tab "Rekap": jumlah foto per hari, per pekan, dan per bulan (dihitung otomatis dari tab data).
function buatRekap_(ss) {
  const sh = ss.getSheetByName(NAMA_SHEET_REKAP) || ss.insertSheet(NAMA_SHEET_REKAP);
  sh.clear();
  const nm = NAMA_SHEET.replace(/'/g, "''");
  const f = (kol, judul) => "=QUERY('" + nm + "'!A2:O,\"select " + kol + ", count(I) where I is not null and " + kol +
    " is not null group by " + kol + " order by " + kol + " desc label " + kol + " '" + judul + "', count(I) 'Jumlah foto'\",0)";
  sh.getRange('A1').setValue('Per hari');
  sh.getRange('D1').setValue('Per pekan (Sabtu sampai Jumat)');
  sh.getRange('G1').setValue('Per bulan');
  sh.getRange('A1:G1').setFontWeight('bold');
  sh.getRange('A2').setFormula(f('L', 'Tanggal'));
  sh.getRange('D2').setFormula(f('M', 'Pekan'));
  sh.getRange('G2').setFormula(f('N', 'Bulan'));
  sh.setColumnWidth(4, 230);
}

// ---------- Menerima foto ----------
function doPost(e) {
  const lock = LockService.getScriptLock();
  try {
    lock.waitLock(20000);
    const d = JSON.parse(e.postData.contents);

    const tim = tim_(d.kode_akses);
    if (!tim) return json_({ ok: false, pesan: 'Kode akses salah.' });

    const lat = Number(d.lat), lng = Number(d.lng);
    if (!isFinite(lat) || !isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return json_({ ok: false, pesan: 'Koordinat tidak valid.' });
    }
    if (!d.foto) return json_({ ok: false, pesan: 'Foto kosong.' });

    const bytes = Utilities.base64Decode(d.foto);
    if (bytes.length > MAKS_BYTE) return json_({ ok: false, pesan: 'Ukuran foto terlalu besar.' });

    // Tanggal kegiatan: dipilih petugas, tidak boleh di masa depan dan tidak terlalu lama.
    const sekarang = new Date();
    const hariIni = tglWib_(sekarang);
    let tanggal = String(d.tanggal || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(tanggal)) tanggal = hariIni;
    if (tglUtc_(geser_(tanggal, 0)) !== tanggal) return json_({ ok: false, pesan: 'Tanggal kegiatan tidak valid.' });
    if (tanggal > hariIni) tanggal = hariIni;
    if (tanggal < tglUtc_(geser_(hariIni, -MAKS_HARI_MUNDUR))) {
      return json_({ ok: false, pesan: 'Tanggal kegiatan terlalu lama (maksimal ' + MAKS_HARI_MUNDUR + ' hari ke belakang).' });
    }
    const inf = info_(tanggal);

    const jam = Utilities.formatDate(sekarang, ZONA_WAKTU, 'HHmmss');
    const bersih = s => String(s || '').replace(/[^A-Za-z0-9_-]+/g, '_').slice(0, 40);
    const namaFile = tanggal.replace(/-/g, '') + '_' + jam + '_' + (bersih(d.kode) || 'tanpa-kode') + '_' + bersih(d.nama) + '.jpg';

    const file = folderTujuan_(tanggal).createFile(Utilities.newBlob(bytes, 'image/jpeg', namaFile));

    // Berbagi per file bisa ditolak (kebijakan akun atau Workspace), jadi dibungkus try/catch: unggahan tetap berhasil.
    // Cara paling andal: bagikan FOLDER_ID sebagai "Siapa saja yang memiliki link - Pelihat"; semua subfolder ikut.
    let bagikan = true;
    try { file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (_) { bagikan = false; }

    // Keterangan juga disimpan di deskripsi file Drive (klik kanan file > Detail).
    try {
      file.setDescription('Petugas: ' + String(d.nama || '') + '\nTim: ' + tim + '\nKode: ' + String(d.kode || '') +
        '\nTanggal kegiatan: ' + tanggal + '\nKeterangan: ' + String(d.keterangan || '') + '\nLokasi: ' + lat + ', ' + lng);
    } catch (_) {}

    try {
      sheet_().appendRow([
        sekarang,
        aman_(d.nama, 80),
        aman_(d.kode, 60),
        aman_(d.keterangan, 300),
        lat,
        lng,
        d.akurasi === '' || d.akurasi == null ? '' : Number(d.akurasi),
        aman_(d.sumber, 60),
        file.getId(),
        true,
        aman_(tim, 60),
        tanggal,
        inf.pekan,
        inf.bulan,
        linkFoto_(file.getId())
      ]);
    } catch (errSheet) {
      file.setTrashed(true);                          // jangan tinggalkan foto tanpa catatan di Sheet
      throw errSheet;
    }

    CacheService.getScriptCache().remove('daftar');
    return json_({ ok: true, id: file.getId(), bagikan: bagikan, folder: inf.bulan + ' / Pekan ' + inf.pekan + ' / ' + inf.tanggal });
  } catch (err) {
    return json_({ ok: false, pesan: String(err) });
  } finally {
    try { lock.releaseLock(); } catch (_) {}
  }
}

// ---------- Mengirim daftar kegiatan ke dashboard ----------
function doGet() {
  const cache = CacheService.getScriptCache();
  let hasil = cache.get('daftar');
  if (!hasil) {
    const baris = sheet_().getDataRange().getValues();
    baris.shift();                                    // buang judul kolom
    const daftar = baris
      .filter(r => r[8] && String(r[9]).toUpperCase() !== 'FALSE')   // kolom "tampil" = FALSE menyembunyikan foto
      .map(r => ({
        w: r[0] instanceof Date ? r[0].toISOString() : r[0],
        tg: tglSel_(r[11], r[0]),
        n: r[1], k: r[2], d: r[3], t: r[10] || '',
        lat: r[4], lng: r[5],
        id: r[8]
      }));
    hasil = JSON.stringify(daftar);
    if (hasil.length < 90000) cache.put('daftar', hasil, 60);        // batas cache sekitar 100 KB
  }
  return ContentService.createTextOutput(hasil).setMimeType(ContentService.MimeType.JSON);
}
